(progn
  #.(progn (in-package #:cl-cc/runtime/observability/test) nil)
  (it-sequential
   "Explicit tracing identifiers, attributes, events, status, and timestamps round-trip."
   (let* ((trace-id "0123456789abcdef0123456789abcdef")
          (span-id "0123456789abcdef")
          (parent-span-id "fedcba9876543210")
          (start-time 1700000000123456789)
          (end-time 1700000001123456789)
          (event-time 1700000000623456789)
          (span
           (make-rt-otel-span :name
                              "request"
                              :trace-id
                              trace-id
                              :span-id
                              span-id
                              :parent-span-id
                              parent-span-id
                              :start
                              start-time
                              :end
                              end-time
                              :attributes
                              '(("http.method" . "GET")
                                ("http.status_code" . 503))
                              :events
                              (list
                               (make-rt-otel-event :name
                                                   "retry"
                                                   :time
                                                   event-time
                                                   :attributes
                                                   '(("attempt" . 2))))
                              :status-code
                              "ERROR"
                              :status-message
                              "upstream unavailable"))
          (attributes (rt-otel-span-attributes span))
          (event (first (rt-otel-span-events span)))
          (json (rt-otel-span-to-json span)))
     (expect (rt-otel-span-trace-id span) :to-equal trace-id)
     (expect (rt-otel-span-span-id span) :to-equal span-id)
     (expect (rt-otel-span-parent-span-id span) :to-equal parent-span-id)
     (expect (gethash "http.method" attributes) :to-equal "GET")
     (expect (gethash "http.status_code" attributes) :to-equal 503)
     (expect (rt-otel-event-name event) :to-equal "retry")
     (expect (rt-otel-event-time event) :to-equal event-time)
     (expect (rt-otel-span-status-code span) :to-equal "ERROR")
     (expect (rt-otel-span-status-message span)
             :to-equal
             "upstream unavailable")
     (expect (rt-otel-span-start span) :to-equal start-time)
     (expect (rt-otel-span-end span) :to-equal end-time)
     (expect (search (format nil "\"traceId\":\"~A\"" trace-id) json)
             :to-be-truthy)
     (expect (search (format nil "\"spanId\":\"~A\"" span-id) json)
             :to-be-truthy)
     (expect (search (format nil "\"parentSpanId\":\"~A\"" parent-span-id) json)
             :to-be-truthy)
     (expect (search "\"http.method\":\"GET\"" json) :to-be-truthy)
     (expect (search "\"http.status_code\":503" json) :to-be-truthy)
     (expect (search "\"name\":\"retry\"" json) :to-be-truthy)
     (expect (search (format nil "\"timeUnixNano\":~D" event-time) json)
             :to-be-truthy)
     (expect (search (format nil "\"startTimeUnixNano\":~D" start-time) json)
             :to-be-truthy)
     (expect (search (format nil "\"endTimeUnixNano\":~D" end-time) json)
             :to-be-truthy)
     (expect (search "\"code\":\"ERROR\"" json) :to-be-truthy)
     (expect (search "\"message\":\"upstream unavailable\"" json) :to-be-truthy)))
  (it-sequential
   "Nested rt-with-span calls preserve context and normalize status codes."
   (let ((outer nil)
         (inner nil))
     (rt-with-span ("outer-operation" :attrs (("scope" . "outer")))
                   (setf outer *rt-otel-span*)
                   (rt-with-span
                    ("inner-operation" :attrs (("scope" . "inner")))
                    (setf inner *rt-otel-span*)
                    (expect (rt-otel-set-status :error "upstream unavailable")
                            :to-equal "ERROR")))
     (expect (rt-otel-span-name outer) :to-equal "outer-operation")
     (expect (rt-otel-span-name inner) :to-equal "inner-operation")
     (expect (rt-otel-span-trace-id inner)
             :to-equal
             (rt-otel-span-trace-id outer))
     (expect (rt-otel-span-parent-span-id inner)
             :to-equal
             (rt-otel-span-span-id outer))
     (expect (rt-otel-span-status-code inner) :to-equal "ERROR")
     (expect (gethash "scope" (rt-otel-span-attributes outer))
             :to-equal
             "outer")
     (expect (gethash "scope" (rt-otel-span-attributes inner))
             :to-equal
             "inner")))
  (it-sequential
   "Mutable span accessors round-trip without ending the active span."
   (let* ((span (rt-otel-start-span "initial-span"))
          (trace-id "0123456789abcdef0123456789abcdef")
          (span-id "0123456789abcdef")
          (parent-span-id "fedcba9876543210")
          (start-time 1700000000123456789)
          (end-time 1700000001123456789)
          (event-time 1700000000623456789)
          (attributes (make-hash-table :test (function equal)))
          (event (make-rt-otel-event
                  :name "mutable-event"
                  :time event-time
                  :attributes (list (cons "event.attribute" "event-value")))))
     (unwind-protect
          (progn
            (setf (rt-otel-span-name span) "mutable-span"
                  (rt-otel-span-trace-id span) trace-id
                  (rt-otel-span-span-id span) span-id
                  (rt-otel-span-parent-span-id span) parent-span-id
                  (rt-otel-span-start span) start-time
                  (rt-otel-span-end span) end-time
                  (rt-otel-span-attributes span) attributes
                  (rt-otel-span-events span) (list event)
                  (rt-otel-span-status-code span) "ERROR"
                  (rt-otel-span-status-message span) "mutable status")
            (setf (gethash "mutable.attribute"
                           (rt-otel-span-attributes span))
                  "visible")
            (expect (eq (rt-otel-span-attributes span) attributes)
                    :to-be-truthy)
            (expect (rt-otel-span-name span) :to-equal "mutable-span")
            (expect (rt-otel-span-trace-id span) :to-equal trace-id)
            (expect (rt-otel-span-span-id span) :to-equal span-id)
            (expect (rt-otel-span-parent-span-id span)
                    :to-equal
                    parent-span-id)
            (expect (rt-otel-span-start span) :to-equal start-time)
            (expect (rt-otel-span-end span) :to-equal end-time)
            (expect (eq (first (rt-otel-span-events span)) event)
                    :to-be-truthy)
            (expect (rt-otel-span-status-code span) :to-equal "ERROR")
            (expect (rt-otel-span-status-message span)
                    :to-equal
                    "mutable status")
            (let ((json (rt-otel-span-to-json span)))
              (expect (search trace-id json) :to-be-truthy)
              (expect (search span-id json) :to-be-truthy)
              (expect (search parent-span-id json) :to-be-truthy)
              (expect (search "mutable-span" json) :to-be-truthy)
              (expect (search "mutable.attribute" json) :to-be-truthy)
              (expect (search "visible" json) :to-be-truthy)
              (expect (search "mutable-event" json) :to-be-truthy)
              (expect (search "event.attribute" json) :to-be-truthy)
              (expect (search "event-value" json) :to-be-truthy)
              (expect (search (format nil "~D" event-time) json)
                      :to-be-truthy)
              (expect (search (format nil "~D" start-time) json)
                      :to-be-truthy)
              (expect (search (format nil "~D" end-time) json)
                      :to-be-truthy)
              (expect (search "ERROR" json) :to-be-truthy)
              (expect (search "mutable status" json) :to-be-truthy))
            (expect (eq *rt-otel-span* span) :to-be-truthy)
            (expect (rt-otel-set-attribute "after-json" "active" span)
                    :to-equal
                    "active")
            (expect (gethash "after-json" (rt-otel-span-attributes span))
                    :to-equal
                    "active")
            (expect (eq *rt-otel-span* span) :to-be-truthy)
            (expect (rt-otel-span-end span) :to-equal end-time))
       (rt-otel-end-span span)))))
