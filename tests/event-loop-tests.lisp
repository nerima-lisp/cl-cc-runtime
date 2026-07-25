;;;; tests/event-loop-tests.lisp
;;;;
;;;; Tests for src/event-loop.lisp — a small fd/timer event loop.  Timer firing
;;;; is made deterministic by scheduling timers with a non-positive delay so
;;;; their deadline is already in the past when the loop ticks.  The fd path is
;;;; exercised with synthetic registrations (the loop calls each registration's
;;;; callback unconditionally, so no real OS descriptor is required).
;;;;
;;;; What is NOT covered here: real readiness-based fd polling.  The
;;;; implementation invokes every registered fd callback on each tick rather than
;;;; polling for actual readiness, so there is no OS-level poll behavior to
;;;; assert against.

(in-package :cl-cc-runtime/test)

(in-suite cl-cc-unit-suite)

;;; ─── Construction ───────────────────────────────────────────────────────────

(deftest event-loop-make-defaults
  "rt-make-event-loop starts un-stopped with the requested tick interval."
  (let ((loop (cl-cc/runtime::rt-make-event-loop :tick-interval 0.005)))
    (assert-false (cl-cc/runtime::rt-event-loop-stopped-p loop))
    (assert-= 0.005 (cl-cc/runtime::rt-event-loop-tick-interval loop))))

;;; ─── fd registration ────────────────────────────────────────────────────────

(deftest event-loop-register-and-unregister-fd
  "register adds an fd->registration entry; unregister removes it."
  (let ((loop (cl-cc/runtime::rt-make-event-loop)))
    (cl-cc/runtime::rt-event-loop-register loop 7 (lambda (reg) (declare (ignore reg))))
    (assert-= 1 (hash-table-count (cl-cc/runtime::rt-event-loop-fds loop)))
    (cl-cc/runtime::rt-event-loop-unregister loop 7)
    (assert-= 0 (hash-table-count (cl-cc/runtime::rt-event-loop-fds loop)))))

(deftest event-loop-register-default-events-is-read
  "A registration defaults to the read-interest event mask."
  (let ((loop (cl-cc/runtime::rt-make-event-loop)))
    (cl-cc/runtime::rt-event-loop-register loop 3 (lambda (r) (declare (ignore r))))
    (let ((reg (gethash 3 (cl-cc/runtime::rt-event-loop-fds loop))))
      (assert-= cl-cc/runtime::+rt-event-read+
                (cl-cc/runtime::rt-event-registration-events reg)))))

(deftest event-loop-run-fds-invokes-callbacks
  "%rt-event-loop-run-fds calls every registered callback with its registration."
  (let ((loop (cl-cc/runtime::rt-make-event-loop))
        (hits nil))
    (cl-cc/runtime::rt-event-loop-register loop 10 (lambda (r) (push (cl-cc/runtime::rt-event-registration-fd r) hits)))
    (cl-cc/runtime::rt-event-loop-register loop 11 (lambda (r) (push (cl-cc/runtime::rt-event-registration-fd r) hits)))
    (cl-cc/runtime::%rt-event-loop-run-fds loop)
    (assert-equal '(10 11) (sort hits #'<))))

;;; ─── Timers ─────────────────────────────────────────────────────────────────

(deftest event-loop-add-timer-sets-future-deadline
  "add-timer schedules a callback with deadline = now + delay."
  (let* ((loop (cl-cc/runtime::rt-make-event-loop))
         (before (cl-cc/runtime::rt-gettime-monotonic))
         (timer (cl-cc/runtime::rt-event-loop-add-timer loop 5.0 (lambda () :fired))))
    (assert-true (>= (cl-cc/runtime::rt-event-timer-deadline timer) (+ before 5.0)))
    (assert-true (member timer (cl-cc/runtime::rt-event-loop-timers loop)))))

(deftest event-loop-due-timer-fires-and-is-removed
  "A one-shot timer whose deadline has passed fires once and is dropped."
  (let ((loop (cl-cc/runtime::rt-make-event-loop))
        (count 0))
    (cl-cc/runtime::rt-event-loop-add-timer loop -1.0 (lambda () (incf count)))
    (cl-cc/runtime::%rt-event-loop-run-timers loop)
    (assert-= 1 count)
    (assert-null (cl-cc/runtime::rt-event-loop-timers loop))))

(deftest event-loop-repeat-timer-rearms
  "A repeating timer fires and stays scheduled with an advanced deadline."
  (let ((loop (cl-cc/runtime::rt-make-event-loop))
        (count 0))
    ;; Large repeat interval so it won't fire again within the test.
    (cl-cc/runtime::rt-event-loop-add-timer loop -1.0 (lambda () (incf count)) :repeat 100.0)
    (cl-cc/runtime::%rt-event-loop-run-timers loop)
    (assert-= 1 count)
    (assert-= 1 (length (cl-cc/runtime::rt-event-loop-timers loop)))
    (let ((timer (first (cl-cc/runtime::rt-event-loop-timers loop))))
      (assert-true (> (cl-cc/runtime::rt-event-timer-deadline timer)
                      (cl-cc/runtime::rt-gettime-monotonic))))))

(deftest event-loop-future-timer-not-fired
  "A timer whose deadline is still in the future does not fire yet."
  (let ((loop (cl-cc/runtime::rt-make-event-loop))
        (count 0))
    (cl-cc/runtime::rt-event-loop-add-timer loop 100.0 (lambda () (incf count)))
    (cl-cc/runtime::%rt-event-loop-run-timers loop)
    (assert-= 0 count)
    (assert-= 1 (length (cl-cc/runtime::rt-event-loop-timers loop)))))

;;; ─── run-once / run / stop ──────────────────────────────────────────────────

(deftest event-loop-run-once-fires-timer-and-fd
  "run-once services both due timers and fd callbacks in a single tick."
  (let ((loop (cl-cc/runtime::rt-make-event-loop :tick-interval 0.001))
        (timer-hits 0)
        (fd-hits 0))
    (cl-cc/runtime::rt-event-loop-add-timer loop -1.0 (lambda () (incf timer-hits)))
    (cl-cc/runtime::rt-event-loop-register loop 1 (lambda (r) (declare (ignore r)) (incf fd-hits)))
    (assert-true (cl-cc/runtime::rt-event-loop-run-once loop :timeout 0.0))
    (assert-= 1 timer-hits)
    (assert-= 1 fd-hits)))

(deftest event-loop-run-stops-at-timeout
  "rt-event-loop-run returns after its timeout budget elapses."
  (let ((loop (cl-cc/runtime::rt-make-event-loop :tick-interval 0.002)))
    (assert-true (cl-cc/runtime::rt-event-loop-run loop :timeout 0.02))))

(deftest event-loop-stop-halts-run
  "Setting the stop flag makes rt-event-loop-run return immediately."
  (let ((loop (cl-cc/runtime::rt-make-event-loop)))
    (cl-cc/runtime::rt-event-loop-stop loop)
    (assert-true (cl-cc/runtime::rt-event-loop-stopped-p loop))
    ;; No timeout: run must exit solely because the stop flag is set.
    (assert-true (cl-cc/runtime::rt-event-loop-run loop))))

;;; ─── Property: N due one-shot timers all fire exactly once ───────────────────

(cl-weave:it-property "every due one-shot timer fires exactly once per tick"
    ((n (cl-weave:gen-integer :min 0 :max 8)))
  (let ((loop (cl-cc/runtime::rt-make-event-loop))
        (count 0))
    (dotimes (i n)
      (cl-cc/runtime::rt-event-loop-add-timer loop -1.0 (lambda () (incf count))))
    (cl-cc/runtime::%rt-event-loop-run-timers loop)
    (and (= count n)
         (null (cl-cc/runtime::rt-event-loop-timers loop)))))
