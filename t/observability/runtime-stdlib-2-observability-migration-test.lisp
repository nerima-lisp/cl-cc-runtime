(in-package :cl-cc/runtime/observability/test)

(it-sequential "runtime-structured-logging-json-and-context"
  :timeout
  5
  (let ((stream (make-string-output-stream)))
    (let ((logger (cl-cc/runtime/observability:make-logger
                   :name "test"
                   :handler (cl-cc/runtime/observability:make-json-handler :stream stream)
                   :level cl-cc/runtime/observability:+level-debug+)))
      (cl-cc/runtime/observability:with-default-logger (logger)
        (cl-cc/runtime/observability:with-log-context (:request-id "r1")
          (cl-cc/runtime/observability:log-default-info "hello" :component "test"))))
    (let ((line (get-output-stream-string stream)))
      ;; Uppercase: cl-log-kit's LEVEL-NAME renders +LEVEL-INFO+ as "INFO".
      (expect (search "\"level\":\"INFO\"" line) :to-be-truthy)
      (expect (search "\"message\":\"hello\"" line) :to-be-truthy)
      (expect (search "\"request-id\":\"r1\"" line) :to-be-truthy)
      (expect (search "\"component\":\"test\"" line) :to-be-truthy)
      (expect (search "\"time\":" line) :to-be-truthy))))

(it-sequential "runtime-metrics-prometheus-output"
  :timeout
  5
  (let ((counter (cl-cc/runtime/observability:rt-make-counter :requests :labels '(:route "/")))
        (gauge (cl-cc/runtime/observability:rt-make-gauge :workers))
        (histogram (cl-cc/runtime/observability:rt-make-histogram :latency '(0.1d0 1.0d0))))
    (cl-cc/runtime/observability:rt-counter-increment! counter 3)
    (cl-cc/runtime/observability:rt-gauge-set! gauge 7)
    (cl-cc/runtime/observability:rt-histogram-observe! histogram 0.05d0)
    (cl-cc/runtime/observability:rt-histogram-observe! histogram 2.0d0)
    (let ((text (cl-cc/runtime/observability:prometheus-text-format (list counter gauge histogram))))
      (expect (search "# TYPE requests counter" text) :to-be-truthy)
      (expect (search "requests{route=\"/\"} 3" text) :to-be-truthy)
      (expect (search "workers 7" text) :to-be-truthy)
      (expect (search "latency_bucket" text) :to-be-truthy)
      (expect (search "latency_count 2" text) :to-be-truthy))))
