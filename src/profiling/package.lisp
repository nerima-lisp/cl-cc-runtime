(defpackage #:cl-cc/runtime/profiling
  (:use #:cl)
  (:import-from #:cl-cc/runtime/concurrency #:rt-make-semaphore #:rt-semaphore-signal #:rt-semaphore-wait)
  (:import-from #:cl-cc/runtime/conditions #:rt-runtime-condition)
  (:import-from #:cl-cc/runtime/memory #:rt-gc-profile-sample #:rt-gc-register-alloc-hook #:rt-gc-stats)
  (:import-from #:cl-cc/runtime/observability
                #:rt-otel-add-event #:rt-otel-end-span #:rt-otel-set-attribute
                #:rt-otel-span-span-id #:rt-otel-span-trace-id #:rt-otel-start-span
                #:%rt-json-attributes #:%rt-json-scalar)
  (:import-from #:cl-cc/runtime/os #:rt-close #:rt-gettime-monotonic #:rt-open #:rt-read #:rt-write)
  (:intern
   #:%rt-profile-collapsed-stack
   #:%rt-profile-normalize-frame
   #:%rt-profile-resolve-perf-symbol
   #:%rt-profile-trim-samples
   #:rt-profile-frame-p
  )
  (:export
   #:*rt-continuous-profile-session*
   #:make-rt-continuous-profile-session
   #:make-rt-profile-frame
   #:make-rt-profile-sample
   #:rt-continuous-profile->otel-span
   #:rt-continuous-profile-session
   #:rt-continuous-profile-session-endpoint
   #:rt-continuous-profile-session-name
   #:rt-continuous-profile-session-output
   #:rt-continuous-profile-session-running-p
   #:rt-continuous-profile-session-sample-log
   #:rt-continuous-profile-session-sample-rate-hz
   #:rt-continuous-profile-session-samples
   #:rt-continuous-profile-session-span-id
   #:rt-continuous-profile-session-trace-id
   #:rt-continuous-profile-to-otel-json
   #:rt-continuous-profile-to-pprof-json
   #:rt-export-continuous-profile
   #:rt-profile-frame
   #:rt-profile-frame-address
   #:rt-profile-frame-function
   #:rt-profile-frame-perf-symbol
   #:rt-profile-frame-source-file
   #:rt-profile-frame-source-line
   #:rt-profile-sample
   #:rt-profile-sample-count
   #:rt-profile-sample-span-id
   #:rt-profile-sample-stack
   #:rt-profile-sample-thread-id
   #:rt-profile-sample-timestamp-nanos
   #:rt-profile-sample-trace-id
   #:rt-record-profile-sample
   #:rt-register-profiling-backend
   #:rt-start-continuous-profile
   #:rt-stop-continuous-profile
   #:rt-wait-for-continuous-profile-sample))



