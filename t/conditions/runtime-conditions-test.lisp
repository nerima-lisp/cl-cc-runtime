;;;; t/runtime-conditions-test.lisp — Coverage for src/runtime-conditions.lisp
;;;;
;;;; Method-dispatch context, the runtime handler/restart condition system, and
;;;; the JIT code cache (LRU/warmth eviction).
(in-package :cl-cc/runtime/conditions/test)

;;; ------------------------------------------------------------
;;; Method-dispatch context
;;; ------------------------------------------------------------
;;; ------------------------------------------------------------
;;; Handler stack
;;; ------------------------------------------------------------
(it-sequential
  "Handlers are found by condition type and dispatched with the condition."
  (let ((cl-cc/runtime/conditions:*handler-stack* nil))
    (cl-cc/runtime/conditions:rt-push-handler
      'error
      (lambda (c)
        (declare (ignore c))
        :handled))
    (expect
      (cl-cc/runtime/conditions:rt-find-handler (make-condition 'simple-error))
      :to-be-truthy)
    (multiple-value-bind (result handled-p) (cl-cc/runtime/conditions:rt-dispatch-signal (make-condition 'simple-error))
      (expect result :to-be :handled)
      (expect handled-p :to-be-truthy))
    (expect (cl-cc/runtime/conditions:rt-pop-handler) :to-be-truthy)
    (expect cl-cc/runtime/conditions:*handler-stack* :to-be-null)))

(it-sequential
  "rt-dispatch-signal returns NIL / NIL when no handler matches."
  (let ((cl-cc/runtime/conditions:*handler-stack* nil))
    (multiple-value-bind (result handled-p) (cl-cc/runtime/conditions:rt-dispatch-signal (make-condition 'simple-error))
      (expect result :to-be-null)
      (expect handled-p :to-be-falsy))))

(it-sequential
  "runtime condition subclasses retain ANSI type relationships."
  (let ((condition (make-condition 'cl-cc/runtime/conditions:rt-division-by-zero)))
    (expect (typep condition 'division-by-zero) :to-be-truthy)
    (expect (typep condition 'arithmetic-error) :to-be-truthy)
    (expect (typep condition 'cl-cc/runtime/conditions:rt-runtime-error) :to-be-truthy)
    (expect (typep condition 'cl-cc/runtime/conditions:rt-runtime-condition) :to-be-truthy)))

(it-sequential
  "rt-establish-handler runs its thunk with the handler and pops it afterwards."
  (let ((cl-cc/runtime/conditions:*handler-stack* nil))
    (cl-cc/runtime/conditions:rt-establish-handler
      'error
      (lambda (c)
        (declare (ignore c))
        1)
      (lambda ()
        (expect (length cl-cc/runtime/conditions:*handler-stack*) :to-equal 1)))
    (expect cl-cc/runtime/conditions:*handler-stack* :to-be-null)))

;;; ------------------------------------------------------------
;;; Restart stack
;;; ------------------------------------------------------------
(it-sequential
  "Restarts are found by name and invoked with args through rt-dispatch-restart."
  (let ((cl-cc/runtime/conditions:*restart-stack* nil))
    (cl-cc/runtime/conditions:rt-push-restart
      'retry
      (lambda (&rest a)
        (declare (ignore a))
        :retried))
    (expect (cl-cc/runtime/conditions:rt-find-restart 'retry) :to-be-truthy)
    (multiple-value-bind (result handled-p) (cl-cc/runtime/conditions:rt-dispatch-restart 'retry nil)
      (expect result :to-be :retried)
      (expect handled-p :to-be-truthy))
    (expect (cl-cc/runtime/conditions:rt-pop-restart) :to-be-truthy)))

(it-sequential
  "rt-dispatch-restart returns NIL / NIL when the restart is not established."
  (let ((cl-cc/runtime/conditions:*restart-stack* nil))
    (multiple-value-bind (result handled-p) (cl-cc/runtime/conditions:rt-dispatch-restart 'nope nil)
      (expect result :to-be-null)
      (expect handled-p :to-be-falsy))))

(it-sequential
  "rt-establish-restart installs one restart for the dynamic extent of the thunk."
  (let ((cl-cc/runtime/conditions:*restart-stack* nil))
    (cl-cc/runtime/conditions:rt-establish-restart
      'go
      (lambda ()
        5)
      (lambda ()
        (expect (cl-cc/runtime/conditions:rt-find-restart 'go) :to-be-truthy)))
    (expect cl-cc/runtime/conditions:*restart-stack* :to-be-null)))

(it-sequential
  "rt-restart-case (via rt-restart-bind) establishes multiple named restarts."
  (let ((cl-cc/runtime/conditions:*restart-stack* nil))
    (cl-cc/runtime/conditions:rt-restart-case
      (lambda ()
        (expect (cl-cc/runtime/conditions:rt-find-restart 'r1) :to-be-truthy)
        (expect (cl-cc/runtime/conditions:rt-find-restart 'r2) :to-be-truthy)
        (multiple-value-bind (result handled-p) (cl-cc/runtime/conditions:rt-dispatch-restart 'r1 nil)
          (expect result :to-equal 1)
          (expect handled-p :to-be-truthy)))
      (list
        (list
          'r1
          (lambda (&rest a)
            (declare (ignore a))
            1))
        (list
          'r2
          (lambda (&rest a)
            (declare (ignore a))
            2))))
    (expect cl-cc/runtime/conditions:*restart-stack* :to-be-null)))

;;; ------------------------------------------------------------
;;; JIT code cache
;;; ------------------------------------------------------------

(in-package :cl-cc/runtime/conditions/test)

(describe "stack-overflow guard (runtime-stack.lisp)"
  (it "rt-check-stack-overflow returns the depth when below the limit"
    (let ((*max-call-stack-depth* 10))
      (expect (cl-cc/runtime/execution:rt-check-stack-overflow 3) :to-be 3)))

  (it "rt-check-stack-overflow signals at the limit"
    (let ((*max-call-stack-depth* 5))
      (signals rt-stack-overflow (cl-cc/runtime/execution:rt-check-stack-overflow 5))))

  (it "the signalled condition carries the offending depth and limit"
    (let ((*max-call-stack-depth* 7))
      (handler-case (cl-cc/runtime/execution:rt-check-stack-overflow 7)
        (rt-stack-overflow (c)
          (expect (rt-stack-overflow-depth c) :to-be 7)
          (expect (rt-stack-overflow-limit c) :to-be 7)))))

  (it "rt-with-call-stack-guard increments the logical depth inside the body"
    (let ((*rt-call-stack-depth* 0))
      (cl-cc/runtime/execution:rt-with-call-stack-guard ()
        (expect *rt-call-stack-depth* :to-be 1))
      ;; depth is restored on exit
      (expect *rt-call-stack-depth* :to-be 0)))

  (it "nested guards eventually trip the overflow condition"
    (let ((*max-call-stack-depth* 4)
          (*rt-call-stack-depth* 0))
      (labels ((recurse () (cl-cc/runtime/execution:rt-with-call-stack-guard () (recurse))))
        (signals rt-stack-overflow (recurse))))))
