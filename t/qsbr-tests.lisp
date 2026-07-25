;;;; t/qsbr-tests.lisp — quiescent-state-based reclamation (src/qsbr.lisp).
(in-package :cl-cc-runtime/test)

(describe "qsbr thread tracking"
  (it "register / unregister adjusts the thread count"
    (rt-qsbr-init)
    (expect (rt-qsbr-thread-count) :to-be 0)
    (rt-qsbr-register-thread)
    (expect (rt-qsbr-thread-count) :to-be 1)
    (rt-qsbr-unregister-thread)
    (expect (rt-qsbr-thread-count) :to-be 0))

  (it "quiescent keeps a registered thread tracked"
    (rt-qsbr-init)
    (rt-qsbr-register-thread)
    (rt-qsbr-quiescent)
    (expect (rt-qsbr-thread-count) :to-be 1)
    (rt-qsbr-unregister-thread)))

;; With no other registered threads the grace period is satisfied immediately,
;; so synchronize behaves as a deterministic two-phase reclamation pipeline:
;; the batch retired before a synchronize is only freed on the FOLLOWING one.
(describe "qsbr deferred reclamation pipeline"
  (it "defers freeing a retired batch by one grace period"
    (let ((freed '()))
      (rt-qsbr-init (lambda (o) (push o freed)))
      (rt-qsbr-retire :a)
      (rt-qsbr-retire :b)
      (rt-qsbr-synchronize)                 ; {a,b} become pending; nothing freed
      (expect freed :to-equal '())
      (rt-qsbr-retire :c)
      (rt-qsbr-synchronize)                 ; a,b freed; {c} becomes pending
      (expect (and (member :a freed) (member :b freed) t) :to-be-truthy)
      (expect (member :c freed) :to-be-null)
      (rt-qsbr-synchronize)                 ; c freed
      (expect (and (member :c freed) t) :to-be-truthy))))

;; Real grace period: synchronize must wait for a registered worker to pass
;; through a quiescent state, then return. The worker keeps announcing
;; quiescence, so the writer is guaranteed to make progress (no hang).
(describe "qsbr under concurrency"
  (it "synchronize completes once a registered worker reports quiescent"
    (rt-qsbr-init)
    (let* ((stop nil)
           (stop-lock (sb-thread:make-mutex))
           (ready (sb-thread:make-semaphore))
           (worker (sb-thread:make-thread
                    (lambda ()
                      (rt-qsbr-register-thread)
                      (sb-thread:signal-semaphore ready)
                      (loop until (sb-thread:with-mutex (stop-lock) stop)
                            do (rt-qsbr-quiescent)
                               (sleep 0.001))))))
      (sb-thread:wait-on-semaphore ready)
      (expect (rt-qsbr-thread-count) :to-be 1)
      (rt-qsbr-retire :obj)
      (rt-qsbr-synchronize)                 ; returns once the worker is quiescent
      (sb-thread:with-mutex (stop-lock) (setf stop t))
      (sb-thread:join-thread worker)
      (expect t :to-be-truthy))))
