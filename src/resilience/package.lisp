(defpackage #:cl-cc/runtime/resilience
  (:use #:cl)
  (:import-from #:resilience-kit
                #:make-rate-limiter
                #:rate-limiter-acquire
                #:rate-limiter-capacity
                #:rate-limiter-last-refill
                #:rate-limiter-refill-rate
                #:rate-limiter-tokens)
  (:intern
   #:rt-token-bucket-accepted
   #:rt-token-bucket-burst
   #:rt-token-bucket-dropped
   #:rt-token-bucket-last
   #:rt-token-bucket-limiter
   #:rt-token-bucket-rate
   #:rt-token-bucket-tokens
   #:rt-token-bucket-try-acquire)
  (:export
   #:rt-make-token-bucket
   #:rt-token-bucket-acquire
   #:rt-token-bucket-stats
   #:rt-token-bucket-wait))



