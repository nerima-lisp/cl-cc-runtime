(defpackage #:cl-cc/runtime/observability
  (:use #:cl)
  (:import-from #:log-kit
                #:+level-debug+ #:+level-info+ #:+level-warn+ #:+level-error+ #:+level-fatal+
                #:*default-logger* #:make-logger #:set-default-logger #:with-default-logger
                #:logger-with #:derive-logger #:logger-child #:with-log-context #:with-log-span
                #:log-debug #:log-info #:log-warn #:log-error #:log-fatal
                #:log-default-debug #:log-default-info #:log-default-warn
                #:log-default-error #:log-default-fatal #:log-condition
                #:make-text-handler #:make-json-handler #:make-function-handler
                #:log-record-fields #:capture-log-context #:with-captured-log-context
                #:call-with-captured-log-context #:log-context-snapshot-p)
  (:import-from #:cl-cc/runtime/memory
                #:rt-gc-current-stats #:rt-gc-stats)
  (:import-from #:observability-kit
                #:define-counter #:define-gauge #:define-histogram
                #:make-meter-provider #:make-meter #:meter-registry
                #:metric-inc #:metric-set #:metric-observe #:metric-snapshot
                #:metric-snapshot-samples #:metric-sample-value #:metric-sample-count
                #:metric-sample-sum #:metric-sample-buckets #:metric-name
                #:proper-list-p
                #:make-tracer-provider #:make-tracer #:make-instrumentation-context
                #:start-span #:end-span #:span-p #:span-name #:span-trace-id #:span-id
                #:span-parent-span-id #:span-start-time #:span-end-time #:span-attributes
                #:span-events #:span-event-name #:span-event-timestamp
                #:span-event-attributes #:span-event-p #:span-status
                #:span-status-message #:span-ended-p #:span-set-attribute
                #:span-add-event #:span-set-status #:span-record-span-id)
  (:import-from #:observability-kit/otlp
                #:span-record->otlp)
  (:import-from #:observability-kit/prometheus
                #:render-prometheus)
  (:intern
   #:%rt-json-attributes
   #:%rt-json-scalar
   #:*rt-metrics-registry*
   #:*rt-meter*
   #:*rt-meter-provider*
   #:rt-counter-value
   #:rt-gauge-value
   #:rt-histogram-buckets
   #:rt-histogram-count
   #:rt-histogram-counts
   #:rt-histogram-sum)
  (:export
   #:*default-logger*
   #:*rt-logger*
   #:*rt-otel-span*
   #:+level-debug+
   #:+level-error+
   #:+level-fatal+
   #:+level-info+
   #:+level-warn+
   #:call-with-captured-log-context
   #:capture-log-context
   #:derive-logger
   #:gc-stats
   #:log-condition
   #:log-context-snapshot-p
   #:log-debug
   #:log-default-debug
   #:log-default-error
   #:log-default-fatal
   #:log-default-info
   #:log-default-warn
   #:log-error
   #:log-fatal
   #:log-info
   #:log-record-fields
   #:log-warn
   #:logger-child
   #:logger-with
   #:make-function-handler
   #:make-json-handler
   #:make-logger
   #:make-rt-otel-event
   #:make-rt-otel-span
   #:make-text-handler
   #:prometheus-text-format
   #:rt-counter-increment!
   #:rt-gauge-set!
   #:rt-histogram-observe!
   #:rt-log
   #:rt-make-counter
   #:rt-make-gauge
   #:rt-make-histogram
   #:rt-metrics-format-prometheus
   #:rt-otel-add-event
   #:rt-otel-end-span
   #:rt-otel-event
   #:rt-otel-event-attributes
   #:rt-otel-event-name
   #:rt-otel-event-time
   #:rt-otel-init
   #:rt-otel-set-attribute
   #:rt-otel-set-status
   #:rt-otel-span
   #:rt-otel-span-attributes
   #:rt-otel-span-end
   #:rt-otel-span-events
   #:rt-otel-span-name
   #:rt-otel-span-parent-span-id
   #:rt-otel-span-span-id
   #:rt-otel-span-start
   #:rt-otel-span-status-code
   #:rt-otel-span-status-message
   #:rt-otel-span-to-json
   #:rt-otel-span-trace-id
   #:rt-otel-start-span
   #:rt-register-metric
   #:rt-with-span
   #:set-default-logger
   #:with-captured-log-context
   #:with-default-logger
   #:with-log-context
   #:with-log-span))



