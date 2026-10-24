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
  (let ((cl-cc/runtime::*handler-stack* nil))
    (cl-cc/runtime::rt-push-handler
      'error
      (lambda (c)
        (declare (ignore c))
        :handled))
    (expect
      (cl-cc/runtime::rt-find-handler (make-condition 'simple-error))
      :to-be-truthy)
    (multiple-value-bind (result handled-p) (cl-cc/runtime::rt-dispatch-signal (make-condition 'simple-error))
      (expect result :to-be :handled)
      (expect handled-p :to-be-truthy))
    (expect (cl-cc/runtime::rt-pop-handler) :to-be-truthy)
    (expect cl-cc/runtime::*handler-stack* :to-be-null)))

(it-sequential
  "rt-dispatch-signal returns NIL / NIL when no handler matches."
  (let ((cl-cc/runtime::*handler-stack* nil))
    (multiple-value-bind (result handled-p) (cl-cc/runtime::rt-dispatch-signal (make-condition 'simple-error))
      (expect result :to-be-null)
      (expect handled-p :to-be-falsy))))

(it-sequential
  "runtime condition subclasses retain ANSI type relationships."
  (let ((condition (make-condition 'cl-cc/runtime:rt-division-by-zero)))
    (expect (typep condition 'division-by-zero) :to-be-truthy)
    (expect (typep condition 'arithmetic-error) :to-be-truthy)
    (expect (typep condition 'cl-cc/runtime:rt-runtime-error) :to-be-truthy)
    (expect (typep condition 'cl-cc/runtime:rt-runtime-condition) :to-be-truthy)))

(it-sequential
  "rt-establish-handler runs its thunk with the handler and pops it afterwards."
  (let ((cl-cc/runtime::*handler-stack* nil))
    (cl-cc/runtime::rt-establish-handler
      'error
      (lambda (c)
        (declare (ignore c))
        1)
      (lambda ()
        (expect (length cl-cc/runtime::*handler-stack*) :to-equal 1)))
    (expect cl-cc/runtime::*handler-stack* :to-be-null)))

;;; ------------------------------------------------------------
;;; Restart stack
;;; ------------------------------------------------------------
(it-sequential
  "Restarts are found by name and invoked with args through rt-dispatch-restart."
  (let ((cl-cc/runtime::*restart-stack* nil))
    (cl-cc/runtime::rt-push-restart
      'retry
      (lambda (&rest a)
        (declare (ignore a))
        :retried))
    (expect (cl-cc/runtime::rt-find-restart 'retry) :to-be-truthy)
    (multiple-value-bind (result handled-p) (cl-cc/runtime::rt-dispatch-restart 'retry nil)
      (expect result :to-be :retried)
      (expect handled-p :to-be-truthy))
    (expect (cl-cc/runtime::rt-pop-restart) :to-be-truthy)))

(it-sequential
  "rt-dispatch-restart returns NIL / NIL when the restart is not established."
  (let ((cl-cc/runtime::*restart-stack* nil))
    (multiple-value-bind (result handled-p) (cl-cc/runtime::rt-dispatch-restart 'nope nil)
      (expect result :to-be-null)
      (expect handled-p :to-be-falsy))))

(it-sequential
  "rt-establish-restart installs one restart for the dynamic extent of the thunk."
  (let ((cl-cc/runtime::*restart-stack* nil))
    (cl-cc/runtime::rt-establish-restart
      'go
      (lambda ()
        5)
      (lambda ()
        (expect (cl-cc/runtime::rt-find-restart 'go) :to-be-truthy)))
    (expect cl-cc/runtime::*restart-stack* :to-be-null)))

(it-sequential
  "rt-restart-case (via rt-restart-bind) establishes multiple named restarts."
  (let ((cl-cc/runtime::*restart-stack* nil))
    (cl-cc/runtime::rt-restart-case
      (lambda ()
        (expect (cl-cc/runtime::rt-find-restart 'r1) :to-be-truthy)
        (expect (cl-cc/runtime::rt-find-restart 'r2) :to-be-truthy)
        (multiple-value-bind (result handled-p) (cl-cc/runtime::rt-dispatch-restart 'r1 nil)
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
    (expect cl-cc/runtime::*restart-stack* :to-be-null)))

;;; ------------------------------------------------------------
;;; JIT code cache
;;; ------------------------------------------------------------
