(defpackage #:cl-cc/runtime/profiling/infra
  (:use #:cl)
  (:import-from #:cl-cc/runtime/conditions #:rt-runtime-condition)
  (:intern
   #:*perf-event-names*
   #:*rt-perf-counters*
   #:rt-perf-counter-enabled
   #:rt-perf-counter-name
   #:rt-perf-counter-type
   #:rt-perf-disable-counter
  )
  (:export
   #:perf-counters-unsupported
   #:rdtsc
   #:rdtscp
   #:rt-perf-enable-counter
   #:rt-perf-init
   #:rt-perf-read-counter
   #:rt-with-perf-counters))



