;;;; t/future-test.lisp
;;;;
;;;; Tests for src/future.lisp — futures/promises backed by a real mutex and
;;;; condition variable.  Covers single/multiple-value resolution, await both
;;;; before and after resolution, the rt-future-then continuation (which spawns
;;;; on the green-thread scheduler), and genuine cross-OS-thread await/resolve
;;;; synchronization.
(in-package :cl-cc-runtime/test)

;;; ─── Basic resolution ───────────────────────────────────────────────────────
(it-sequential
  "rt-future-resolve stores a value; rt-future-await returns it, done-p is set."
  (let ((f (cl-cc/runtime::rt-make-future)))
    (expect (cl-cc/runtime::rt-future-done-p f) :to-be-falsy)
    (cl-cc/runtime::rt-future-resolve f :answer)
    (expect (cl-cc/runtime::rt-future-done-p f) :to-be-truthy)
    (expect (cl-cc/runtime::rt-future-await f) :to-be :answer)))

(it-sequential
  "A future resolved with several values yields all of them from await."
  (let ((f (cl-cc/runtime::rt-make-future)))
    (cl-cc/runtime::rt-future-resolve f 1 2 3)
    (multiple-value-bind (a b c) (cl-cc/runtime::rt-future-await f)
      (expect a :to-equal 1)
      (expect b :to-equal 2)
      (expect c :to-equal 3))))

(it-sequential
  "Awaiting an already-resolved future does not block."
  (let ((f (cl-cc/runtime::rt-make-future)))
    (cl-cc/runtime::rt-future-resolve f :ready)
    (expect (cl-cc/runtime::rt-future-await f :timeout 0.01) :to-be :ready)))

(it-sequential "Awaiting a never-resolved future with a timeout returns (no values) once the
deadline passes — it neither hangs nor errors — and the future stays pending.
The wait actually spans roughly the requested timeout rather than returning
instantly." (let* ((f (cl-cc/runtime::rt-make-future))
         (timeout 0.05)
         (start (get-internal-real-time))
         (result (multiple-value-list (cl-cc/runtime::rt-future-await f :timeout timeout)))
         (elapsed (/ (- (get-internal-real-time) start)
                     (float internal-time-units-per-second))))
    (expect result :to-be-null)
    (expect (cl-cc/runtime::rt-future-done-p f) :to-be-falsy)
    ;; It genuinely waited (allowing scheduling slack), not a busy return.
    (expect (>= elapsed (* 0.5 timeout)) :to-be-truthy)))

(it-sequential "A generous timeout does not cut the wait short: a future resolved partway
through the budget is awaited to its value, well before the deadline." (let* ((f (cl-cc/runtime::rt-make-future))
         (result-box (list nil))
         (start (get-internal-real-time))
         (waiter (sb-thread:make-thread
                  (lambda ()
                    ;; 5s budget, but resolution arrives in ~20ms.
                    (setf (first result-box) (cl-cc/runtime::rt-future-await f :timeout 5.0)))
                  :name "future-timeout-waiter")))
    (sleep 0.02)
    (cl-cc/runtime::rt-future-resolve f :in-time)
    (sb-thread:join-thread waiter)
    (let ((elapsed (/ (- (get-internal-real-time) start)
                      (float internal-time-units-per-second))))
      (expect (first result-box) :to-be :in-time)
      ;; Returned on resolution, nowhere near the 5s deadline.
      (expect (< elapsed 2.0) :to-be-truthy))))

(it-sequential
  "rt-all-futures returns its argument list after awaiting every future."
  (let ((fs
        (list
          (cl-cc/runtime::rt-make-future)
          (cl-cc/runtime::rt-make-future)
          (cl-cc/runtime::rt-make-future))))
    (loop for f in fs
          for i from 0
          do (cl-cc/runtime::rt-future-resolve f i))
    (expect (cl-cc/runtime::rt-all-futures fs) :to-be fs)
    (expect (every #'cl-cc/runtime::rt-future-done-p fs) :to-be-truthy)))

;;; ─── rt-future-then (scheduler-driven continuation) ─────────────────────────
(it-sequential "rt-future-then spawns a green thread that awaits the source future and
resolves the derived future with the callback's result." (cl-cc/runtime::rt-scheduler-init)
  (let* ((src (cl-cc/runtime::rt-make-future))
         (derived (cl-cc/runtime::rt-future-then src (lambda (x) (* x 10)))))
    (cl-cc/runtime::rt-future-resolve src 7)
    ;; Drain the scheduler so the spawned continuation runs.
    (cl-cc/runtime::rt-scheduler-run)
    (expect (cl-cc/runtime::rt-future-done-p derived) :to-be-truthy)
    (expect (cl-cc/runtime::rt-future-await derived) :to-equal 70)))

;;; ─── Genuine cross-thread synchronization ───────────────────────────────────
(it-sequential "A future awaited on one OS thread is unblocked by a resolve on another,
proving the condition-variable handoff works across real threads." (let* ((f (cl-cc/runtime::rt-make-future))
         (result-box (list nil))
         (waiter (sb-thread:make-thread
                  (lambda ()
                    (setf (first result-box) (cl-cc/runtime::rt-future-await f)))
                  :name "future-waiter")))
    ;; Give the waiter a moment to block, then resolve from this thread.
    (sleep 0.02)
    (cl-cc/runtime::rt-future-resolve f :from-other-thread)
    (sb-thread:join-thread waiter)
    (expect (first result-box) :to-be :from-other-thread)))

;;; ─── Property: any resolved value round-trips through await ──────────────────
(cl-weave:it-property
  "future round-trips arbitrary resolved integers"
  ((n (cl-weave:gen-integer :min -1000 :max 1000)))
  (let ((f (cl-cc/runtime::rt-make-future)))
    (cl-cc/runtime::rt-future-resolve f n)
    (and
      (cl-cc/runtime::rt-future-done-p f)
      (eql n (cl-cc/runtime::rt-future-await f)))))
