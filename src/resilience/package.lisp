(defpackage #:cl-cc/runtime/resilience
  (:use #:cl)
  (:import-from #:cl-cc/runtime/os #:rt-gettime-monotonic)
  (:intern
   #:rt-token-bucket-accepted
   #:rt-token-bucket-burst
   #:rt-token-bucket-dropped
   #:rt-token-bucket-last
   #:rt-token-bucket-rate
   #:rt-token-bucket-refill
   #:rt-token-bucket-tokens
   #:rt-token-bucket-try-acquire
  )
  (:export
   #:rt-make-token-bucket
   #:rt-token-bucket-acquire
   #:rt-token-bucket-stats
   #:rt-token-bucket-wait))



