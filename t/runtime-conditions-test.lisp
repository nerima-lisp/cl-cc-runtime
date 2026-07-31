;;;; t/runtime-conditions-test.lisp — Coverage for src/runtime-conditions.lisp
;;;;
;;;; Method-dispatch context, the runtime handler/restart condition system, and
;;;; the JIT code cache (LRU/warmth eviction).
(in-package :cl-cc-runtime/test)

;;; ------------------------------------------------------------
;;; Method-dispatch context
;;; ------------------------------------------------------------
(it-sequential
  "rt-call-next-method reuses the frame args by default and honours new args."
  (let ((cl-cc/runtime::*rt-method-context-stack*
        (list
          (list
            :next-thunk
            (lambda (args)
              (apply #'+ args))
            :args
            '(1 2 3)))))
    (expect (cl-cc/runtime::rt-next-method-p) :to-be-truthy)
    (expect (cl-cc/runtime::rt-call-next-method) :to-equal 6)
    (expect (cl-cc/runtime::rt-call-next-method 10 20) :to-equal 30)))

(it-sequential
  "With no context, rt-next-method-p is false and rt-call-next-method errors."
  (let ((cl-cc/runtime::*rt-method-context-stack* nil))
    (expect (cl-cc/runtime::rt-next-method-p) :to-be-falsy)
    (signals error (cl-cc/runtime::rt-call-next-method))))

(it-sequential
  "rt-register-function installs a global function definition."
  (cl-cc/runtime::rt-register-function
    'rt-cond-test-triple
    (lambda (x)
      (* 3 x)))
  (expect (funcall 'rt-cond-test-triple 4) :to-equal 12))

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
(it-sequential
  "Storing and looking up code updates hit/miss counters and occupancy."
  (let ((cache (cl-cc/runtime::make-rt-code-cache :capacity 100)))
    (expect (cl-cc/runtime::rt-code-cache-lookup 'f1 cache) :to-be-null)
    (cl-cc/runtime::rt-code-cache-store 'f1 :code-1 :size 10 :cache cache)
    (expect (cl-cc/runtime::rt-code-cache-lookup 'f1 cache) :to-be :code-1)
    (let ((stats (cl-cc/runtime::rt-code-cache-stats cache)))
      (expect (getf stats :hits) :to-equal 1)
      (expect (getf stats :misses) :to-equal 1)
      (expect (getf stats :size) :to-equal 10)
      (expect (getf stats :entries) :to-equal 1))))

(it-sequential
  "rt-code-cache-evict removes an entry and decrements occupancy."
  (let ((cache (cl-cc/runtime::make-rt-code-cache :capacity 100)))
    (cl-cc/runtime::rt-code-cache-store 'g :code-g :size 4 :cache cache)
    (expect (cl-cc/runtime::rt-code-cache-evict 'g cache) :to-be-truthy)
    (expect (cl-cc/runtime::rt-code-cache-lookup 'g cache) :to-be-null)
    (expect (getf (cl-cc/runtime::rt-code-cache-stats cache) :size) :to-equal 0)))

(it-sequential
  "Storing beyond capacity evicts the coldest entry."
  (let ((cache (cl-cc/runtime::make-rt-code-cache :capacity 10)))
    (cl-cc/runtime::rt-code-cache-store 'a :code-a :size 6 :cache cache)
    (cl-cc/runtime::rt-code-cache-store 'b :code-b :size 6 :cache cache)
    (expect
      (plusp (getf (cl-cc/runtime::rt-code-cache-stats cache) :evictions))
      :to-be-truthy)
    (expect (cl-cc/runtime::rt-code-cache-lookup 'a cache) :to-be-null)
    (expect (cl-cc/runtime::rt-code-cache-lookup 'b cache) :to-be :code-b)))

(it-sequential
  "rt-gc-unload-code removes a cache entry by function-entry key or by code value."
  (let ((cache (cl-cc/runtime::make-rt-code-cache :capacity 100)))
    (cl-cc/runtime::rt-code-cache-store 'k1 :code-k1 :size 3 :cache cache)
    (expect (cl-cc/runtime::rt-gc-unload-code nil 'k1 cache) :to-be-truthy)
    (expect (cl-cc/runtime::rt-code-cache-lookup 'k1 cache) :to-be-null)
    (cl-cc/runtime::rt-code-cache-store 'k2 :shared-code :size 2 :cache cache)
    (let ((removed (cl-cc/runtime::rt-gc-unload-code nil :shared-code cache)))
      (expect removed :to-be-truthy)
      (expect (cl-cc/runtime::rt-code-cache-lookup 'k2 cache) :to-be-null))))
