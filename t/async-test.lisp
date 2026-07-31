;;;; t/async-test.lisp — Coverage for src/async.lisp
;;;;
;;;; Exercises the async/await surface (FR-741): the CPS transformer's actual
;;;; expansion, the rt-async-cps macro's runtime resolution, and suspend/resume
;;;; of async tasks through the green scheduler.
(in-package :cl-cc-runtime/test)

;;; WITH-FRESH-SCHEDULER is defined once, in scheduler-test.lisp (which loads
;;; before this file per the .asd's :serial ordering): a fresh scheduler is
;;; bound per-test so async submissions never leak green threads across tests
;;; or depend on prior global scheduler state. This file used to carry its own
;;; narrower redefinition that reset only *RT-GLOBAL-SCHEDULER*, silently
;;; shadowing scheduler-test.lisp's fuller version (which also resets
;;; *RT-CURRENT-GREEN-THREAD*) for this file's own tests below.

;;; ------------------------------------------------------------
;;; CPS transform — structural expansion
;;; ------------------------------------------------------------
(it-sequential
  "An atom becomes a direct continuation call."
  (expect (cl-cc/runtime:rt-async-cps-transform 5 'k) :to-equal '(funcall k 5)))

(it-sequential
  "An RT-AWAIT form chains through rt-future-then with the continuation."
  (expect
    (cl-cc/runtime:rt-async-cps-transform '(cl-cc/runtime:rt-await fut) 'k)
    :to-equal
    '(cl-cc/runtime:rt-future-then fut k)))

(it-sequential
  "An empty PROGN calls the continuation with NIL."
  (expect
    (cl-cc/runtime:rt-async-cps-transform
      '(progn)
      'k)
    :to-equal
    '(funcall k nil)))

(it-sequential
  "IF is transformed into an IF whose branches each invoke the continuation."
  (expect
    (cl-cc/runtime:rt-async-cps-transform
      '(if test then
        else)
      'k)
    :to-equal
    '(if test (funcall k then)
      (funcall k else))))

(it-sequential
  "WHEN desugars to an IF with an implicit NIL else, both arms continuation-wrapped."
  (expect
    (cl-cc/runtime:rt-async-cps-transform
      '(when test then)
      'k)
    :to-equal
    '(if test (funcall k then)
      (funcall k nil))))

(it-sequential
  "UNLESS desugars to an IF with an implicit NIL then, both arms continuation-wrapped."
  (expect
    (cl-cc/runtime:rt-async-cps-transform
      '(unless test else)
      'k)
    :to-equal
    '(if test (funcall k nil)
      (funcall k else))))

(it-sequential
  "COND desugars to nested IFs, each clause continuation-wrapped."
  (expect
    (cl-cc/runtime:rt-async-cps-transform
      '(cond (c1 b1) (c2 b2))
      'k)
    :to-equal
    '(if c1 (funcall k b1)
      (if c2 (funcall k b2)
        (funcall k nil)))))

(it-sequential
  "A bodyless COND clause returns its own test, matching CL's COND."
  (expect
    (cl-cc/runtime:rt-async-cps-transform
      '(cond (c1))
      'k)
    :to-equal
    '(if c1 (funcall k c1)
      (funcall k nil))))

(it-sequential
  "A non-await call is left in direct style wrapped by the continuation."
  (expect
    (cl-cc/runtime:rt-async-cps-transform '(some-fn 1 2) 'k)
    :to-equal
    '(funcall k (some-fn 1 2))))

(it-sequential
  "LET keeps its bindings and transforms the body as an implicit PROGN."
  (expect
    (cl-cc/runtime:rt-async-cps-transform
      '(let ((a 1))
        a)
      'k)
    :to-equal
    '(let ((a 1))
      (funcall k a))))

;;; ------------------------------------------------------------
;;; rt-async-cps — runtime resolution
;;; ------------------------------------------------------------
(it-sequential
  "Without any await, rt-async-cps resolves the future to the final value now."
  (let ((fut (cl-cc/runtime:rt-async-cps 10 20 30)))
    (expect (cl-cc/runtime:rt-future-done-p fut) :to-be-truthy)
    (expect (cl-cc/runtime:rt-future-await fut) :to-equal 30)))

(it-sequential
  "rt-async-cps over an rt-await resolves once the scheduler drains the task."
  (with-fresh-scheduler
    (let ((f (cl-cc/runtime:rt-make-future)))
      (cl-cc/runtime:rt-future-resolve f 7)
      (let ((result (cl-cc/runtime:rt-async-cps (cl-cc/runtime:rt-await f))))
        (expect (cl-cc/runtime:rt-future-done-p result) :to-be-falsy)
        (cl-cc/runtime:rt-scheduler-run)
        (expect (cl-cc/runtime:rt-future-await result) :to-equal 7)))))

;;; ------------------------------------------------------------
;;; rt-async / rt-async-submit / rt-await
;;; ------------------------------------------------------------
(it-sequential
  "rt-async-submit schedules a thunk whose future resolves after a scheduler run."
  (with-fresh-scheduler
    (let ((fut
          (cl-cc/runtime:rt-async-submit
            (lambda ()
              (+ 1 2)))))
      (expect (cl-cc/runtime:rt-future-done-p fut) :to-be-falsy)
      (cl-cc/runtime:rt-scheduler-run)
      (expect (cl-cc/runtime:rt-future-done-p fut) :to-be-truthy)
      (expect (cl-cc/runtime:rt-future-await fut) :to-equal 3))))

(it-sequential
  "rt-async plus rt-await drive the task to completion via the scheduler."
  (with-fresh-scheduler
    (let ((fut (cl-cc/runtime:rt-async (* 6 7))))
      (expect (cl-cc/runtime:rt-await fut) :to-equal 42))))

(it-sequential
  "A signalling thunk resolves its future to the condition instead of unwinding."
  (with-fresh-scheduler
    (let ((fut
          (cl-cc/runtime:rt-async-submit
            (lambda ()
              (error "boom")))))
      (cl-cc/runtime:rt-scheduler-run)
      (expect (cl-cc/runtime:rt-future-done-p fut) :to-be-truthy)
      (expect (typep (cl-cc/runtime:rt-future-await fut) (quote error)) :to-be-truthy))))

(it-sequential
  "rt-await gives up promptly, not after blocking forever, once TIMEOUT elapses on a future that never resolves"
  ;; The polling loop inside RT-AWAIT* used to check only whether the future
  ;; had resolved, ignoring TIMEOUT entirely: it would spin until the future
  ;; resolved no matter what timeout was requested. This bounds real elapsed
  ;; time to prove that regression stays fixed rather than just checking the
  ;; return value, which a re-introduced infinite loop would never reach.
  (with-fresh-scheduler
    (let* ((f (cl-cc/runtime:rt-make-future))
           (started (get-internal-real-time)))
      (expect (multiple-value-list (cl-cc/runtime:rt-await f :timeout 0.05)) :to-equal nil)
      (expect
        (< (- (get-internal-real-time) started) internal-time-units-per-second)
        :to-be-truthy))))

(it-sequential
  "rt-async-lambda returns a function that starts its body asynchronously."
  (with-fresh-scheduler
    (let* ((square (cl-cc/runtime:rt-async-lambda (x) (* x x)))
           (fut (funcall square 5)))
      (expect (cl-cc/runtime:rt-await fut) :to-equal 25))))

;;; rt-async-defun expands to a defun; define at top level and drive it.
(cl-cc/runtime:rt-async-defun async-test-double (n) (* 2 n))

(it-sequential
  "rt-async-defun defines a function returning a future."
  (with-fresh-scheduler
    (let ((fut (async-test-double 21)))
      (expect (cl-cc/runtime:rt-await fut) :to-equal 42))))

;;; ------------------------------------------------------------
;;; rt-async-channel / send / recv
;;; ------------------------------------------------------------
(it-sequential
  "rt-async-channel builds a channel with the requested capacity."
  (let ((ch (cl-cc/runtime:rt-async-channel :capacity 3)))
    (expect (cl-cc/runtime::rt-channel-capacity ch) :to-equal 3)))

(it-sequential
  "rt-async-send then rt-async-recv move a value through a buffered channel."
  (with-fresh-scheduler
    (let* ((ch (cl-cc/runtime:rt-async-channel :capacity 1))
           (send-future (cl-cc/runtime:rt-async-send ch 99)))
      (cl-cc/runtime:rt-scheduler-run)
      (expect (cl-cc/runtime:rt-future-await send-future) :to-equal 99)
      (let ((recv-future (cl-cc/runtime:rt-async-recv ch)))
        (cl-cc/runtime:rt-scheduler-run)
        (expect (cl-cc/runtime:rt-future-await recv-future) :to-equal 99)))))
