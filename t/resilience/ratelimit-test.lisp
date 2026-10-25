;;;; t/ratelimit-test.lisp — token-bucket rate limiter (src/ratelimit.lisp).
(in-package :cl-cc/runtime/resilience/test)

(describe
  "token bucket construction (ratelimit.lisp)"
  (it
    "starts with its configured burst capacity"
    (let ((bucket
            (cl-cc/runtime/resilience:rt-make-token-bucket
             :rate 0.0
             :burst 20.0)))
      (expect (rt-token-bucket-try-acquire bucket 20)
              :to-be-truthy)
      (expect (rt-token-bucket-try-acquire bucket)
              :to-be-null)))
  (it
    "inherits kit validation for capacity and refill rate"
    (expect
     (lambda ()
       (cl-cc/runtime/resilience:rt-make-token-bucket :burst 0))
     :to-throw
     'error)
    (expect
     (lambda ()
       (cl-cc/runtime/resilience:rt-make-token-bucket :rate -1))
     :to-throw
     'error)))

(describe
  "token bucket acquisition and wait (ratelimit.lisp)"
  (it
    "try-acquire succeeds while tokens remain, counting accepts"
    (let ((bucket
            (cl-cc/runtime/resilience:rt-make-token-bucket :rate 0.0 :burst 3.0)))
      (expect (rt-token-bucket-try-acquire bucket)
              :to-be-truthy)
      (expect (rt-token-bucket-try-acquire bucket)
              :to-be-truthy)
      (expect (rt-token-bucket-try-acquire bucket)
              :to-be-truthy)
      (expect (rt-token-bucket-accepted bucket) :to-be 3)))
  (it
    "try-acquire fails once the bucket is empty, counting a drop"
    (let ((bucket
            (cl-cc/runtime/resilience:rt-make-token-bucket :rate 0.0 :burst 1.0)))
      (expect (rt-token-bucket-try-acquire bucket)
              :to-be-truthy)
      (expect (rt-token-bucket-try-acquire bucket)
              :to-be-null)
      (expect (rt-token-bucket-dropped bucket) :to-be 1)))
  (it
    "try-acquire can claim several tokens at once"
    (let ((bucket
            (cl-cc/runtime/resilience:rt-make-token-bucket :rate 0.0 :burst 10.0)))
      (expect (rt-token-bucket-try-acquire bucket 4)
              :to-be-truthy)
      (expect (getf (cl-cc/runtime/resilience:rt-token-bucket-stats bucket) :tokens)
              :to-equal 6d0)))
  (it
    "rejects a request larger than capacity without consuming tokens"
    (let ((bucket
            (cl-cc/runtime/resilience:rt-make-token-bucket :rate 0.0 :burst 2.0)))
      (expect (rt-token-bucket-try-acquire bucket 3)
              :to-be-null)
      (let ((stats (cl-cc/runtime/resilience:rt-token-bucket-stats bucket)))
        (expect (getf stats :tokens) :to-equal 2d0)
        (expect (getf stats :dropped) :to-be 1))
      (expect (rt-token-bucket-try-acquire bucket 2)
              :to-be-truthy)))
  (it
    "rt-token-bucket-acquire is an alias for try-acquire"
    (let ((bucket
            (cl-cc/runtime/resilience:rt-make-token-bucket :rate 0.0 :burst 1.0)))
      (expect (cl-cc/runtime/resilience:rt-token-bucket-acquire bucket)
              :to-be-truthy)
      (expect (cl-cc/runtime/resilience:rt-token-bucket-acquire bucket)
              :to-be-null)))
  (it
    "inherits kit validation for nonpositive requests"
    (let ((bucket
            (cl-cc/runtime/resilience:rt-make-token-bucket :rate 0.0 :burst 1.0)))
      (expect
       (lambda () (rt-token-bucket-try-acquire bucket 0))
       :to-throw
       'error)))
  (it
    "wait returns immediately when a token is available"
    (let ((bucket
            (cl-cc/runtime/resilience:rt-make-token-bucket :rate 1000.0 :burst 5.0)))
      (expect (cl-cc/runtime/resilience:rt-token-bucket-wait bucket) :to-be-truthy)))
  (it
    "wait retries until refill makes the request available"
    (let ((bucket
            (cl-cc/runtime/resilience:rt-make-token-bucket :rate 10.0 :burst 1.0)))
      (rt-token-bucket-try-acquire bucket)
      (expect
       (cl-cc/runtime/resilience:rt-token-bucket-wait bucket 1 :timeout 1.0)
       :to-be-truthy)))
  (it
    "wait returns nil when the timeout is shorter than retry-after"
    (let ((bucket
            (cl-cc/runtime/resilience:rt-make-token-bucket :rate 1.0 :burst 1.0)))
      (rt-token-bucket-try-acquire bucket)
      (expect
       (cl-cc/runtime/resilience:rt-token-bucket-wait bucket 1 :timeout 0.05)
       :to-be-null)))
  (it
    "wait rejects requests larger than capacity without waiting"
    (let ((bucket
            (cl-cc/runtime/resilience:rt-make-token-bucket :rate 1.0 :burst 1.0)))
      (expect (cl-cc/runtime/resilience:rt-token-bucket-wait bucket 2) :to-be-null)
      (expect (rt-token-bucket-dropped bucket) :to-be 1)))
  (it
    "wait rejects an exhausted bucket that cannot refill"
    (let ((bucket
            (cl-cc/runtime/resilience:rt-make-token-bucket :rate 0.0 :burst 1.0)))
      (rt-token-bucket-try-acquire bucket)
      (expect (cl-cc/runtime/resilience:rt-token-bucket-wait bucket) :to-be-null)
      (expect (rt-token-bucket-dropped bucket) :to-be 1))))

(describe
  "token bucket refill (ratelimit.lisp)"
  (it
    "delegates elapsed-time refill and the burst cap to the kit"
    (let ((bucket
            (cl-cc/runtime/resilience:rt-make-token-bucket :rate 1000.0 :burst 2.0)))
      (expect (rt-token-bucket-try-acquire bucket 2)
              :to-be-truthy)
      (sleep 0.02)
      (expect (rt-token-bucket-try-acquire bucket 3)
              :to-be-null)
      (expect (rt-token-bucket-try-acquire bucket 2)
              :to-be-truthy)
      (expect (getf (cl-cc/runtime/resilience:rt-token-bucket-stats bucket) :tokens)
              :to-equal 0d0)))
  (it
    "refills at the configured rate below the burst cap"
    (let ((bucket
            (cl-cc/runtime/resilience:rt-make-token-bucket :rate 4.0 :burst 100.0)))
      (expect (rt-token-bucket-acquire bucket 100)
              :to-be-truthy)
      (sleep 1.0)
      (expect (rt-token-bucket-acquire bucket 6)
              :to-be-null)
      (expect (rt-token-bucket-acquire bucket 3)
              :to-be-truthy)
      (let ((tokens
              (getf (cl-cc/runtime/resilience:rt-token-bucket-stats bucket) :tokens)))
        (expect (<= 0d0 tokens 3d0) :to-be-truthy)))))

(describe
  "token bucket stats (ratelimit.lisp)"
  (it
    "reports kit tokens and wrapper accepted and dropped counters"
    (let ((bucket
            (cl-cc/runtime/resilience:rt-make-token-bucket :rate 0.0 :burst 2.0)))
      (rt-token-bucket-try-acquire bucket)
      (rt-token-bucket-try-acquire bucket)
      (rt-token-bucket-try-acquire bucket)
      (let ((stats (cl-cc/runtime/resilience:rt-token-bucket-stats bucket)))
        (expect (getf stats :accepted) :to-be 2)
        (expect (getf stats :dropped) :to-be 1)
        (expect (getf stats :tokens) :to-equal 0d0)))))
(describe
  "token bucket concurrent statistics"
  (it
    "records all concurrent accepted and dropped requests"
    (let* ((thread-count 8)
           (iterations 500)
           (accepted-bucket
             (cl-cc/runtime/resilience:rt-make-token-bucket :rate 0.0 :burst (* thread-count iterations)))
           (dropped-bucket (cl-cc/runtime/resilience:rt-make-token-bucket :rate 0.0 :burst 1.0))
           (ready (sb-thread:make-semaphore :count 0))
           (start (sb-thread:make-semaphore :count 0))
           (threads nil)
           (workers-released nil))
      (unwind-protect
           (progn
             (loop repeat thread-count
                   do (push
                       (sb-thread:make-thread
                        (lambda ()
                          (sb-thread:signal-semaphore ready)
                          (sb-thread:wait-on-semaphore start)
                          (loop repeat iterations
                                do (progn
                                     (cl-cc/runtime/resilience:rt-token-bucket-acquire accepted-bucket)
                                     (cl-cc/runtime/resilience:rt-token-bucket-acquire dropped-bucket 2)))))
                       threads))
             (loop repeat thread-count do (sb-thread:wait-on-semaphore ready))
             (loop repeat thread-count do (sb-thread:signal-semaphore start))
             (setf workers-released t)
             (dolist (thread threads)
               (sb-thread:join-thread thread))
             (let ((accepted-stats (cl-cc/runtime/resilience:rt-token-bucket-stats accepted-bucket))
                   (dropped-stats (cl-cc/runtime/resilience:rt-token-bucket-stats dropped-bucket)))
               (expect (getf accepted-stats :accepted)
                       :to-be (* thread-count iterations))
               (expect (getf accepted-stats :dropped) :to-be 0)
               (expect (getf dropped-stats :accepted) :to-be 0)
               (expect (getf dropped-stats :dropped)
                       :to-be (* thread-count iterations))))
        (progn
          (unless workers-released
            (loop repeat thread-count do (sb-thread:signal-semaphore start)))
          (dolist (thread threads)
            (ignore-errors (sb-thread:join-thread thread))))))))
