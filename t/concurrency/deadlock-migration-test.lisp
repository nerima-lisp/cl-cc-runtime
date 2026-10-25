(in-package :cl-cc/runtime/concurrency/test)

(defmacro with-clean-deadlock-state (&body body)
  "Run BODY with a freshly initialized deadlock detector, restoring state after."
  `(let ((cl-cc/runtime/concurrency:*rt-dl-enabled* nil)
         (cl-cc/runtime/concurrency:*rt-dl-thread-locks* (make-hash-table :test #'eq))
         (cl-cc/runtime/concurrency:*rt-dl-thread-waits* (make-hash-table :test #'eq)))
     ,@body))

(it-sequential "deadlock-detect-disabled-by-default"
  (with-clean-deadlock-state
    (expect cl-cc/runtime/concurrency:*rt-dl-enabled* :to-be-falsy)
    (expect (cl-cc/runtime/concurrency:rt-deadlock-detect) :to-be-falsy)))

(it-sequential "deadlock-detect-no-cycle-single-thread"
  (with-clean-deadlock-state
    (setf cl-cc/runtime/concurrency:*rt-dl-enabled* t)
    (cl-cc/runtime/concurrency:rt-deadlock-after-lock 'lock-a 'thread-1 t)
    (expect (cl-cc/runtime/concurrency:rt-deadlock-detect) :to-be-falsy)))

(it-sequential "deadlock-detect-two-thread-cycle"
  (with-clean-deadlock-state
    (setf cl-cc/runtime/concurrency:*rt-dl-enabled* t)
    ;; thread-1 holds lock-a, waits for lock-b
    (cl-cc/runtime/concurrency:rt-deadlock-after-lock 'lock-a 'thread-1 t)
    (cl-cc/runtime/concurrency:rt-deadlock-before-lock 'lock-b 'thread-1)
    ;; thread-2 holds lock-b, waits for lock-a
    (cl-cc/runtime/concurrency:rt-deadlock-after-lock 'lock-b 'thread-2 t)
    (cl-cc/runtime/concurrency:rt-deadlock-before-lock 'lock-a 'thread-2)
    (expect (cl-cc/runtime/concurrency:rt-deadlock-detect) :to-be-truthy)))

(it-sequential "deadlock-after-unlock-removes-held-lock"
  (with-clean-deadlock-state
    (setf cl-cc/runtime/concurrency:*rt-dl-enabled* t)
    (cl-cc/runtime/concurrency:rt-deadlock-after-lock 'lock-x 'thread-1 t)
    (cl-cc/runtime/concurrency:rt-deadlock-after-unlock 'lock-x 'thread-1)
    ;; After unlock, thread-1 should have no held locks — no deadlock possible
    (expect (cl-cc/runtime/concurrency:rt-deadlock-detect) :to-be-falsy)))

(it-sequential "deadlock-init-clears-all-state"
  (with-clean-deadlock-state
    (setf cl-cc/runtime/concurrency:*rt-dl-enabled* t)
    (cl-cc/runtime/concurrency:rt-deadlock-after-lock 'lock-a 'thread-1 t)
    (cl-cc/runtime/concurrency:rt-deadlock-init)
    (expect cl-cc/runtime/concurrency:*rt-dl-enabled* :to-be-falsy)
    (expect (= 0 (hash-table-count cl-cc/runtime/concurrency:*rt-dl-thread-locks*)) :to-be-truthy)
    (expect (= 0 (hash-table-count cl-cc/runtime/concurrency:*rt-dl-thread-waits*)) :to-be-truthy)))
