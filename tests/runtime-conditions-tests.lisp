;;;; tests/runtime-conditions-tests.lisp — Coverage for src/runtime-conditions.lisp
;;;;
;;;; Method-dispatch context, the runtime handler/restart condition system, and
;;;; the JIT code cache (LRU/warmth eviction).

(in-package :cl-cc-runtime/test)

(in-suite cl-cc-unit-suite)

;;; ------------------------------------------------------------
;;; Method-dispatch context
;;; ------------------------------------------------------------

(deftest conditions-call-next-method-reuses-and-replaces-args
  "rt-call-next-method reuses the frame args by default and honours new args."
  (let ((cl-cc/runtime::*rt-method-context-stack*
          (list (list :next-thunk (lambda (args) (apply #'+ args))
                      :args '(1 2 3)))))
    (assert-true (cl-cc/runtime::rt-next-method-p))
    (assert-= 6 (cl-cc/runtime::rt-call-next-method))
    (assert-= 30 (cl-cc/runtime::rt-call-next-method 10 20))))

(deftest conditions-call-next-method-absent
  "With no context, rt-next-method-p is false and rt-call-next-method errors."
  (let ((cl-cc/runtime::*rt-method-context-stack* nil))
    (assert-false (cl-cc/runtime::rt-next-method-p))
    (assert-signals error (cl-cc/runtime::rt-call-next-method))))

(deftest conditions-register-function
  "rt-register-function installs a global function definition."
  (cl-cc/runtime::rt-register-function 'rt-cond-test-triple
                                       (lambda (x) (* 3 x)))
  (assert-= 12 (funcall 'rt-cond-test-triple 4)))

;;; ------------------------------------------------------------
;;; Handler stack
;;; ------------------------------------------------------------

(deftest conditions-handler-push-find-dispatch
  "Handlers are found by condition type and dispatched with the condition."
  (let ((cl-cc/runtime::*handler-stack* nil))
    (cl-cc/runtime::rt-push-handler 'error
                                    (lambda (c) (declare (ignore c)) :handled))
    (assert-true (cl-cc/runtime::rt-find-handler (make-condition 'simple-error)))
    (multiple-value-bind (result handled-p)
        (cl-cc/runtime::rt-dispatch-signal (make-condition 'simple-error))
      (assert-eq :handled result)
      (assert-true handled-p))
    (assert-true (cl-cc/runtime::rt-pop-handler))
    (assert-null cl-cc/runtime::*handler-stack*)))

(deftest conditions-dispatch-signal-unhandled
  "rt-dispatch-signal returns NIL / NIL when no handler matches."
  (let ((cl-cc/runtime::*handler-stack* nil))
    (multiple-value-bind (result handled-p)
        (cl-cc/runtime::rt-dispatch-signal (make-condition 'simple-error))
      (assert-null result)
      (assert-false handled-p))))

(deftest conditions-establish-handler-unwinds
  "rt-establish-handler runs its thunk with the handler and pops it afterwards."
  (let ((cl-cc/runtime::*handler-stack* nil))
    (cl-cc/runtime::rt-establish-handler
     'error (lambda (c) (declare (ignore c)) 1)
     (lambda () (assert-= 1 (length cl-cc/runtime::*handler-stack*))))
    (assert-null cl-cc/runtime::*handler-stack*)))

;;; ------------------------------------------------------------
;;; Restart stack
;;; ------------------------------------------------------------

(deftest conditions-restart-push-find-dispatch
  "Restarts are found by name and invoked with args through rt-dispatch-restart."
  (let ((cl-cc/runtime::*restart-stack* nil))
    (cl-cc/runtime::rt-push-restart 'retry
                                    (lambda (&rest a) (declare (ignore a)) :retried))
    (assert-true (cl-cc/runtime::rt-find-restart 'retry))
    (multiple-value-bind (result handled-p)
        (cl-cc/runtime::rt-dispatch-restart 'retry nil)
      (assert-eq :retried result)
      (assert-true handled-p))
    (assert-true (cl-cc/runtime::rt-pop-restart))))

(deftest conditions-dispatch-restart-missing
  "rt-dispatch-restart returns NIL / NIL when the restart is not established."
  (let ((cl-cc/runtime::*restart-stack* nil))
    (multiple-value-bind (result handled-p)
        (cl-cc/runtime::rt-dispatch-restart 'nope nil)
      (assert-null result)
      (assert-false handled-p))))

(deftest conditions-establish-restart-unwinds
  "rt-establish-restart installs one restart for the dynamic extent of the thunk."
  (let ((cl-cc/runtime::*restart-stack* nil))
    (cl-cc/runtime::rt-establish-restart
     'go (lambda () 5)
     (lambda () (assert-true (cl-cc/runtime::rt-find-restart 'go))))
    (assert-null cl-cc/runtime::*restart-stack*)))

(deftest conditions-restart-bind-and-case
  "rt-restart-case (via rt-restart-bind) establishes multiple named restarts."
  (let ((cl-cc/runtime::*restart-stack* nil))
    (cl-cc/runtime::rt-restart-case
     (lambda ()
       (assert-true (cl-cc/runtime::rt-find-restart 'r1))
       (assert-true (cl-cc/runtime::rt-find-restart 'r2))
       (multiple-value-bind (result handled-p)
           (cl-cc/runtime::rt-dispatch-restart 'r1 nil)
         (assert-= 1 result)
         (assert-true handled-p)))
     (list (list 'r1 (lambda (&rest a) (declare (ignore a)) 1))
           (list 'r2 (lambda (&rest a) (declare (ignore a)) 2))))
    (assert-null cl-cc/runtime::*restart-stack*)))

;;; ------------------------------------------------------------
;;; JIT code cache
;;; ------------------------------------------------------------

(deftest conditions-code-cache-store-lookup-stats
  "Storing and looking up code updates hit/miss counters and occupancy."
  (let ((cache (cl-cc/runtime::make-rt-code-cache :capacity 100)))
    (assert-null (cl-cc/runtime::rt-code-cache-lookup 'f1 cache))
    (cl-cc/runtime::rt-code-cache-store 'f1 :code-1 :size 10 :cache cache)
    (assert-eq :code-1 (cl-cc/runtime::rt-code-cache-lookup 'f1 cache))
    (let ((stats (cl-cc/runtime::rt-code-cache-stats cache)))
      (assert-= 1 (getf stats :hits))
      (assert-= 1 (getf stats :misses))
      (assert-= 10 (getf stats :size))
      (assert-= 1 (getf stats :entries)))))

(deftest conditions-code-cache-evict
  "rt-code-cache-evict removes an entry and decrements occupancy."
  (let ((cache (cl-cc/runtime::make-rt-code-cache :capacity 100)))
    (cl-cc/runtime::rt-code-cache-store 'g :code-g :size 4 :cache cache)
    (assert-true (cl-cc/runtime::rt-code-cache-evict 'g cache))
    (assert-null (cl-cc/runtime::rt-code-cache-lookup 'g cache))
    (assert-= 0 (getf (cl-cc/runtime::rt-code-cache-stats cache) :size))))

(deftest conditions-code-cache-capacity-eviction
  "Storing beyond capacity evicts the coldest entry."
  (let ((cache (cl-cc/runtime::make-rt-code-cache :capacity 10)))
    (cl-cc/runtime::rt-code-cache-store 'a :code-a :size 6 :cache cache)
    (cl-cc/runtime::rt-code-cache-store 'b :code-b :size 6 :cache cache)
    (assert-true (plusp (getf (cl-cc/runtime::rt-code-cache-stats cache) :evictions)))
    (assert-null (cl-cc/runtime::rt-code-cache-lookup 'a cache))
    (assert-eq :code-b (cl-cc/runtime::rt-code-cache-lookup 'b cache))))

(deftest conditions-gc-unload-code-by-key-and-value
  "rt-gc-unload-code removes a cache entry by function-entry key or by code value."
  (let ((cache (cl-cc/runtime::make-rt-code-cache :capacity 100)))
    (cl-cc/runtime::rt-code-cache-store 'k1 :code-k1 :size 3 :cache cache)
    (assert-true (cl-cc/runtime::rt-gc-unload-code nil 'k1 cache))
    (assert-null (cl-cc/runtime::rt-code-cache-lookup 'k1 cache))
    (cl-cc/runtime::rt-code-cache-store 'k2 :shared-code :size 2 :cache cache)
    (let ((removed (cl-cc/runtime::rt-gc-unload-code nil :shared-code cache)))
      (assert-true removed)
      (assert-null (cl-cc/runtime::rt-code-cache-lookup 'k2 cache)))))
