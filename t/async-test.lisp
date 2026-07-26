;;;; t/async-test.lisp — Coverage for src/async.lisp
;;;;
;;;; Exercises the async/await surface (FR-741): the CPS transformer's actual
;;;; expansion, the rt-async-cps macro's runtime resolution, and suspend/resume
;;;; of async tasks through the green scheduler.

(in-package :cl-cc-runtime/test)

(in-suite cl-cc-unit-suite)

;;; A fresh scheduler is bound per-test so async submissions never leak green
;;; threads across tests or depend on prior global scheduler state.
(defmacro with-fresh-scheduler (&body body)
  `(let ((cl-cc/runtime::*rt-global-scheduler* (cl-cc/runtime::rt-make-scheduler)))
     ,@body))

;;; ------------------------------------------------------------
;;; CPS transform — structural expansion
;;; ------------------------------------------------------------

(deftest async-cps-transform-atom
  "An atom becomes a direct continuation call."
  (assert-equal '(funcall k 5)
                (cl-cc/runtime:rt-async-cps-transform 5 'k)))

(deftest async-cps-transform-await
  "An RT-AWAIT form chains through rt-future-then with the continuation."
  (assert-equal '(cl-cc/runtime:rt-future-then fut k)
                (cl-cc/runtime:rt-async-cps-transform '(cl-cc/runtime:rt-await fut) 'k)))

(deftest async-cps-transform-empty-progn
  "An empty PROGN calls the continuation with NIL."
  (assert-equal '(funcall k nil)
                (cl-cc/runtime:rt-async-cps-transform '(progn) 'k)))

(deftest async-cps-transform-if-splits-branches
  "IF is transformed into an IF whose branches each invoke the continuation."
  (assert-equal '(if test (funcall k then) (funcall k else))
                (cl-cc/runtime:rt-async-cps-transform '(if test then else) 'k)))

(deftest async-cps-transform-plain-call-direct
  "A non-await call is left in direct style wrapped by the continuation."
  (assert-equal '(funcall k (some-fn 1 2))
                (cl-cc/runtime:rt-async-cps-transform '(some-fn 1 2) 'k)))

(deftest async-cps-transform-let-wraps-body
  "LET keeps its bindings and transforms the body as an implicit PROGN."
  (assert-equal '(let ((a 1)) (funcall k a))
                (cl-cc/runtime:rt-async-cps-transform '(let ((a 1)) a) 'k)))

;;; ------------------------------------------------------------
;;; rt-async-cps — runtime resolution
;;; ------------------------------------------------------------

(deftest async-cps-resolves-last-value-synchronously
  "Without any await, rt-async-cps resolves the future to the final value now."
  (let ((fut (cl-cc/runtime:rt-async-cps 10 20 30)))
    (assert-true (cl-cc/runtime:rt-future-done-p fut))
    (assert-= 30 (cl-cc/runtime:rt-future-await fut))))

(deftest async-cps-await-resolves-through-scheduler
  "rt-async-cps over an rt-await resolves once the scheduler drains the task."
  (with-fresh-scheduler
    (let ((f (cl-cc/runtime:rt-make-future)))
      (cl-cc/runtime:rt-future-resolve f 7)
      (let ((result (cl-cc/runtime:rt-async-cps (cl-cc/runtime:rt-await f))))
        (assert-false (cl-cc/runtime:rt-future-done-p result))
        (cl-cc/runtime:rt-scheduler-run)
        (assert-= 7 (cl-cc/runtime:rt-future-await result))))))

;;; ------------------------------------------------------------
;;; rt-async / rt-async-submit / rt-await
;;; ------------------------------------------------------------

(deftest async-submit-returns-future-resolved-after-run
  "rt-async-submit schedules a thunk whose future resolves after a scheduler run."
  (with-fresh-scheduler
    (let ((fut (cl-cc/runtime:rt-async-submit (lambda () (+ 1 2)))))
      (assert-false (cl-cc/runtime:rt-future-done-p fut))
      (cl-cc/runtime:rt-scheduler-run)
      (assert-true (cl-cc/runtime:rt-future-done-p fut))
      (assert-= 3 (cl-cc/runtime:rt-future-await fut)))))

(deftest async-macro-and-await-cooperate
  "rt-async plus rt-await drive the task to completion via the scheduler."
  (with-fresh-scheduler
    (let ((fut (cl-cc/runtime:rt-async (* 6 7))))
      (assert-= 42 (cl-cc/runtime:rt-await fut)))))

(deftest async-submit-captures-error-as-value
  "A signalling thunk resolves its future to the condition instead of unwinding."
  (with-fresh-scheduler
    (let ((fut (cl-cc/runtime:rt-async-submit
                (lambda () (error "boom")))))
      (cl-cc/runtime:rt-scheduler-run)
      (assert-true (cl-cc/runtime:rt-future-done-p fut))
      (assert-type error (cl-cc/runtime:rt-future-await fut)))))

(deftest async-lambda-builds-async-thunk
  "rt-async-lambda returns a function that starts its body asynchronously."
  (with-fresh-scheduler
    (let* ((square (cl-cc/runtime:rt-async-lambda (x) (* x x)))
           (fut (funcall square 5)))
      (assert-= 25 (cl-cc/runtime:rt-await fut)))))

;;; rt-async-defun expands to a defun; define at top level and drive it.
(cl-cc/runtime:rt-async-defun async-test-double (n) (* 2 n))

(deftest async-defun-defines-async-function
  "rt-async-defun defines a function returning a future."
  (with-fresh-scheduler
    (let ((fut (async-test-double 21)))
      (assert-= 42 (cl-cc/runtime:rt-await fut)))))

;;; ------------------------------------------------------------
;;; rt-async-channel / send / recv
;;; ------------------------------------------------------------

(deftest async-channel-created-with-capacity
  "rt-async-channel builds a channel with the requested capacity."
  (let ((ch (cl-cc/runtime:rt-async-channel :capacity 3)))
    (assert-= 3 (cl-cc/runtime::rt-channel-capacity ch))))

(deftest async-channel-send-recv-roundtrip
  "rt-async-send then rt-async-recv move a value through a buffered channel."
  (with-fresh-scheduler
    (let* ((ch (cl-cc/runtime:rt-async-channel :capacity 1))
           (send-future (cl-cc/runtime:rt-async-send ch 99)))
      (cl-cc/runtime:rt-scheduler-run)
      (assert-= 99 (cl-cc/runtime:rt-future-await send-future))
      (let ((recv-future (cl-cc/runtime:rt-async-recv ch)))
        (cl-cc/runtime:rt-scheduler-run)
        (assert-= 99 (cl-cc/runtime:rt-future-await recv-future))))))
