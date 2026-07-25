;;;; tests/rcu-tests.lisp — read-copy-update (src/rcu.lisp).
(in-package :cl-cc-runtime/test)

(defvar *rcu-test-ptr* nil)

(describe "rcu pointer publication"
  (it "assign-pointer and dereference round-trip through a symbol's value"
    (rt-rcu-assign-pointer '*rcu-test-ptr* 42)
    (expect (rt-rcu-dereference '*rcu-test-ptr*) :to-be 42)
    (expect *rcu-test-ptr* :to-be 42)
    (rt-rcu-assign-pointer '*rcu-test-ptr* :next)
    (expect (rt-rcu-dereference '*rcu-test-ptr*) :to-be :next)))

(describe "rcu reader bookkeeping"
  (it "read-lock and read-unlock balance the reader count"
    (rt-rcu-init)
    (rt-rcu-read-lock)
    (expect (gethash sb-thread:*current-thread* cl-cc/runtime::*rt-rcu-readers*) :to-be 1)
    (rt-rcu-read-lock)
    (expect (gethash sb-thread:*current-thread* cl-cc/runtime::*rt-rcu-readers*) :to-be 2)
    (cl-cc/runtime::rt-rcu-read-unlock)
    (cl-cc/runtime::rt-rcu-read-unlock)
    (expect (hash-table-count cl-cc/runtime::*rt-rcu-readers*) :to-be 0))

  (it "rt-with-rcu-read runs the body and releases the reader afterwards"
    (rt-rcu-init)
    (let ((result (rt-with-rcu-read ()
                    (expect (gethash sb-thread:*current-thread*
                                     cl-cc/runtime::*rt-rcu-readers*)
                            :to-be 1)
                    :body-value)))
      (expect result :to-be :body-value))
    (expect (hash-table-count cl-cc/runtime::*rt-rcu-readers*) :to-be 0)))

(describe "rcu synchronization"
  (it "synchronize returns immediately when there are no readers"
    (rt-rcu-init)
    (expect (rt-rcu-synchronize) :to-be-truthy))

  (it "rt-rcu-call runs the callback after synchronize"
    (rt-rcu-init)
    (expect (rt-rcu-call #'+ 2 3) :to-be 5))

  ;; Grace period under real concurrency: a writer's synchronize must not
  ;; return until every reader that was already inside a critical section
  ;; leaves it.
  (it "synchronize blocks until an in-flight reader finishes"
    (rt-rcu-init)
    (let* ((reader-locked (sb-thread:make-semaphore))
           (release (sb-thread:make-semaphore))
           (sync-lock (sb-thread:make-mutex))
           (sync-done nil)
           (reader (sb-thread:make-thread
                    (lambda ()
                      (rt-rcu-read-lock)
                      (sb-thread:signal-semaphore reader-locked)
                      (sb-thread:wait-on-semaphore release)
                      (cl-cc/runtime::rt-rcu-read-unlock)))))
      (sb-thread:wait-on-semaphore reader-locked)   ; reader now holds the lock
      (let ((writer (sb-thread:make-thread
                     (lambda ()
                       (rt-rcu-synchronize)
                       (sb-thread:with-mutex (sync-lock) (setf sync-done t))))))
        (sleep 0.05)
        (expect (sb-thread:with-mutex (sync-lock) sync-done) :to-be-null)
        (sb-thread:signal-semaphore release)        ; reader leaves its section
        (sb-thread:join-thread writer)
        (expect sync-done :to-be-truthy))
      (sb-thread:join-thread reader)))

  (it "rt-rcu-init returns t"
    (expect (rt-rcu-init) :to-be-truthy)))
