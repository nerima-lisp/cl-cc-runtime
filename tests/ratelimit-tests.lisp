;;;; tests/ratelimit-tests.lisp — token-bucket rate limiter (src/ratelimit.lisp).
(in-package :cl-cc-runtime/test)

(describe "token bucket construction (ratelimit.lisp)"
  (it "starts full: initial tokens equal the burst"
    (let ((b (cl-cc/runtime::rt-make-token-bucket :rate 5.0 :burst 20.0)))
      (expect (cl-cc/runtime::rt-token-bucket-tokens b) :to-equal 20.0)
      (expect (cl-cc/runtime::rt-token-bucket-burst b) :to-equal 20.0)
      (expect (cl-cc/runtime::rt-token-bucket-rate b) :to-equal 5.0))))

(describe "token bucket acquisition (ratelimit.lisp)"
  (it "try-acquire succeeds while tokens remain, decrementing and counting accepts"
    (let ((b (cl-cc/runtime::rt-make-token-bucket :rate 0.0 :burst 3.0)))
      (expect (cl-cc/runtime::rt-token-bucket-try-acquire b) :to-be-truthy)
      (expect (cl-cc/runtime::rt-token-bucket-try-acquire b) :to-be-truthy)
      (expect (cl-cc/runtime::rt-token-bucket-try-acquire b) :to-be-truthy)
      (expect (cl-cc/runtime::rt-token-bucket-accepted b) :to-be 3)))

  (it "try-acquire fails once the bucket is empty, counting a drop"
    ;; rate 0 => no refill, so 1 token then exhaustion is deterministic.
    (let ((b (cl-cc/runtime::rt-make-token-bucket :rate 0.0 :burst 1.0)))
      (expect (cl-cc/runtime::rt-token-bucket-try-acquire b) :to-be-truthy)
      (expect (cl-cc/runtime::rt-token-bucket-try-acquire b) :to-be-null)
      (expect (cl-cc/runtime::rt-token-bucket-dropped b) :to-be 1)))

  (it "try-acquire can claim several tokens at once"
    (let ((b (cl-cc/runtime::rt-make-token-bucket :rate 0.0 :burst 10.0)))
      (expect (cl-cc/runtime::rt-token-bucket-try-acquire b 4) :to-be-truthy)
      (expect (cl-cc/runtime::rt-token-bucket-tokens b) :to-equal 6.0)))

  (it "requesting more than the bucket holds is refused"
    (let ((b (cl-cc/runtime::rt-make-token-bucket :rate 0.0 :burst 2.0)))
      (expect (cl-cc/runtime::rt-token-bucket-try-acquire b 5) :to-be-null)
      (expect (cl-cc/runtime::rt-token-bucket-tokens b) :to-equal 2.0)))

  (it "rt-token-bucket-acquire is an alias for try-acquire"
    (let ((b (cl-cc/runtime::rt-make-token-bucket :rate 0.0 :burst 1.0)))
      (expect (cl-cc/runtime::rt-token-bucket-acquire b) :to-be-truthy)
      (expect (cl-cc/runtime::rt-token-bucket-acquire b) :to-be-null)))

  (it "rt-token-bucket-wait returns immediately when a token is available"
    (let ((b (cl-cc/runtime::rt-make-token-bucket :rate 1000.0 :burst 5.0)))
      (expect (cl-cc/runtime::rt-token-bucket-wait b) :to-be-truthy))))

(describe "token bucket refill (ratelimit.lisp)"
  (it "refill adds rate*elapsed tokens but never exceeds the burst cap"
    (let ((b (cl-cc/runtime::rt-make-token-bucket :rate 100.0 :burst 10.0)))
      ;; Drain, then rewind the last-refill timestamp one second into the past:
      ;; 100 tokens/s * 1s = 100 requested, clamped to the burst of 10.
      (setf (cl-cc/runtime::rt-token-bucket-tokens b) 0.0
            (cl-cc/runtime::rt-token-bucket-last b)
            (- (cl-cc/runtime::rt-gettime-monotonic) 1.0))
      (cl-cc/runtime::rt-token-bucket-refill b)
      (expect (cl-cc/runtime::rt-token-bucket-tokens b) :to-equal 10.0)))

  (it "refill partially replenishes below the cap"
    (let ((b (cl-cc/runtime::rt-make-token-bucket :rate 4.0 :burst 100.0)))
      (setf (cl-cc/runtime::rt-token-bucket-tokens b) 0.0
            (cl-cc/runtime::rt-token-bucket-last b)
            (- (cl-cc/runtime::rt-gettime-monotonic) 1.0))
      (let ((tokens (cl-cc/runtime::rt-token-bucket-refill b)))
        ;; ~4 tokens after 1s; allow slack for scheduling jitter in the clock.
        (expect (<= 3.0 tokens 6.0) :to-be-truthy)))))

(describe "token bucket stats (ratelimit.lisp)"
  (it "stats reports live token, accepted, and dropped counters"
    (let ((b (cl-cc/runtime::rt-make-token-bucket :rate 0.0 :burst 2.0)))
      (cl-cc/runtime::rt-token-bucket-try-acquire b)   ; accept
      (cl-cc/runtime::rt-token-bucket-try-acquire b)   ; accept
      (cl-cc/runtime::rt-token-bucket-try-acquire b)   ; drop
      (let ((stats (cl-cc/runtime::rt-token-bucket-stats b)))
        (expect (getf stats :accepted) :to-be 2)
        (expect (getf stats :dropped) :to-be 1)
        (expect (getf stats :tokens) :to-equal 0.0)))))
