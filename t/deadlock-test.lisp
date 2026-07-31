(in-package :cl-cc-runtime/test)

(defmacro with-clean-deadlock-state (&body body)
  "Run BODY with a freshly initialized deadlock detector, restoring state after."
  `(let ((cl-cc/runtime::*rt-dl-enabled* nil)
        (cl-cc/runtime::*rt-dl-thread-locks* (make-hash-table :test #'eq))
        (cl-cc/runtime::*rt-dl-thread-waits* (make-hash-table :test #'eq)))
    ,@body))

(it-sequential
  "rt-deadlock-detect returns nil when *rt-dl-enabled* is nil (the default)."
  (with-clean-deadlock-state
    (expect cl-cc/runtime::*rt-dl-enabled* :to-be-falsy)
    (expect (cl-cc/runtime::rt-deadlock-detect) :to-be-falsy)))

(it-sequential
  "rt-deadlock-detect returns nil when only one thread holds a lock with no waits."
  (with-clean-deadlock-state
    (setf cl-cc/runtime::*rt-dl-enabled* t)
    (cl-cc/runtime::rt-deadlock-after-lock 'lock-a 'thread-1 t)
    (expect (cl-cc/runtime::rt-deadlock-detect) :to-be-falsy)))

(it-sequential "rt-deadlock-detect identifies a two-thread A-waits-B, B-waits-A cycle." (with-clean-deadlock-state
    (setf cl-cc/runtime::*rt-dl-enabled* t)
    ;; thread-1 holds lock-a, waits for lock-b
    (cl-cc/runtime::rt-deadlock-after-lock 'lock-a 'thread-1 t)
    (cl-cc/runtime::rt-deadlock-before-lock 'lock-b 'thread-1)
    ;; thread-2 holds lock-b, waits for lock-a
    (cl-cc/runtime::rt-deadlock-after-lock 'lock-b 'thread-2 t)
    (cl-cc/runtime::rt-deadlock-before-lock 'lock-a 'thread-2)
    (expect (cl-cc/runtime::rt-deadlock-detect) :to-be-truthy)))

(it-sequential "rt-deadlock-after-unlock removes the lock from the thread's held-lock list." (with-clean-deadlock-state
    (setf cl-cc/runtime::*rt-dl-enabled* t)
    (cl-cc/runtime::rt-deadlock-after-lock 'lock-x 'thread-1 t)
    (cl-cc/runtime::rt-deadlock-after-unlock 'lock-x 'thread-1)
    ;; After unlock, thread-1 should have no held locks — no deadlock possible
    (expect (cl-cc/runtime::rt-deadlock-detect) :to-be-falsy)))

(it-sequential
  "rt-deadlock-init resets all tracking tables and leaves detection disabled."
  (with-clean-deadlock-state
    (setf cl-cc/runtime::*rt-dl-enabled* t)
    (cl-cc/runtime::rt-deadlock-after-lock 'lock-a 'thread-1 t)
    (cl-cc/runtime::rt-deadlock-init)
    (expect cl-cc/runtime::*rt-dl-enabled* :to-be-falsy)
    (expect (hash-table-count cl-cc/runtime::*rt-dl-thread-locks*) :to-equal 0)
    (expect (hash-table-count cl-cc/runtime::*rt-dl-thread-waits*) :to-equal 0)))
