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
                               (make-rt-otel-event :name "retry"
                                                   :time event-time
                                                   :attributes (list (cons "attempt" 2)))
                               (make-rt-otel-event :name "fallback"
                                                   :time (+ event-time 1000000000)
                                                   :attributes (list (cons "attempt" 3))))
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
     (expect (mapcar (function rt-otel-event-name)
                     (rt-otel-span-events span))
             :to-equal
             (list "retry" "fallback"))
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
   "Span accessors project kit state and preserve runtime event order."
   (let* ((span (rt-otel-start-span "initial-span"))
          (first-event-time 1700000000623456789)
          (second-event-time 1700000000123456789))
     (unwind-protect
         (progn
           (setf (rt-otel-span-name span) "updated-span")
           (rt-otel-set-attribute "visible" "adapter-value" span)
           (setf (rt-otel-span-status-code span) "ERROR"
                 (rt-otel-span-status-message span) "adapter status")
           (let ((event-attributes
                    (make-hash-table :test (function equal))))
             (setf (gethash "event.attribute" event-attributes) "first-value")
             (let ((added-event
                    (rt-otel-add-event
                     "first-event"
                     :attributes event-attributes
                     :timestamp-nanos first-event-time
                     :span span)))
               (expect (rt-otel-event-name added-event) :to-equal "first-event")
               (expect (rt-otel-event-time added-event)
                       :to-equal
                       first-event-time)
               (expect (rt-otel-event-attributes added-event)
                       :to-equal
                       (list (cons "event.attribute" "first-value")))))
           (rt-otel-add-event
            "second-event"
            :attributes (list (cons "event.attribute" "second-value"))
            :timestamp-nanos second-event-time
            :span span)
           (expect (rt-otel-span-name span) :to-equal "updated-span")
           (expect (gethash "visible" (rt-otel-span-attributes span))
                   :to-equal
                   "adapter-value")
           (expect (rt-otel-span-status-code span) :to-equal "ERROR")
           (expect (rt-otel-span-status-message span)
                   :to-equal
                   "adapter status")
           (expect (mapcar (function rt-otel-event-name)
                           (rt-otel-span-events span))
                   :to-equal
                   (list "second-event" "first-event"))
           (expect (rt-otel-event-time (first (rt-otel-span-events span)))
                   :to-equal
                   second-event-time)
           (let ((attributes (rt-otel-span-attributes span)))
             (setf (gethash "copy-only" attributes) "detached")
             (expect (gethash "copy-only"
                              (rt-otel-span-attributes span))
                     :to-equal
                     nil))
           (let* ((json (rt-otel-span-to-json span))
                  (first-position (search "first-event" json))
                  (second-position (search "second-event" json)))
             (expect (search "updated-span" json) :to-be-truthy)
             (expect (search "adapter-value" json) :to-be-truthy)
             (expect (and first-position
                          second-position
                          (< first-position second-position))
                     :to-be-truthy))
           (expect (rt-otel-set-attribute "after-json" "active" span)
                   :to-equal
                   "active")
           (expect (gethash "after-json" (rt-otel-span-attributes span))
                   :to-equal
                   "active")
           (expect (eq *rt-otel-span* span) :to-be-truthy)
           (rt-otel-end-span span)
           (expect (plusp (rt-otel-span-end span)) :to-be-truthy)
           (expect (null *rt-otel-span*) :to-be-truthy))
       (unless (plusp (rt-otel-span-end span))
         (rt-otel-end-span span))))))
