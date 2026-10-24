;;;; packages/runtime/src/continuous-profile-export.lisp — FR-701 continuous
;;;; profile export: JSON, OTel profiles signal, and pprof-JSON encodings

(in-package :cl-cc/runtime/profiling)

(progn
  (defun %rt-profile-json-scalar (value)
    (cond
      ((null value) json-kit:+json-null+)
      ((eq value t) t)
      ((numberp value) value)
      ((stringp value) value)
      (t (princ-to-string value))))
  (defun %rt-profile-json-attributes (attributes)
    (let ((members nil))
      (cond
        ((hash-table-p attributes)
         (maphash (lambda (key value)
                    (push (cons (princ-to-string key)
                                (%rt-profile-json-scalar value))
                          members))
                  attributes))
        ((and (proper-list-p attributes)
              (every (lambda (attribute)
                       (and (proper-list-p attribute)
                            (every #'consp attribute)
                            (assoc "key" attribute :test #'string=)
                            (assoc "value" attribute :test #'string=)))
                     attributes))
         (dolist (attribute attributes)
           (let ((key (assoc "key" attribute :test #'string=))
                 (value (assoc "value" attribute :test #'string=)))
             (push (cons (princ-to-string (cdr key))
                         (%rt-profile-json-scalar (cdr value)))
                   members))))
        (t
         (dolist (pair attributes)
           (push (cons (princ-to-string (car pair))
                       (%rt-profile-json-scalar (cdr pair)))
                 members))))
      (json-kit:make-json-object (nreverse members))))
  (defun %rt-profile-frame->json (frame)
    "Build a JSON object describing one resolved profile FRAME."
    (json-kit:make-json-object
     (list (cons "function" (rt-profile-frame-function frame))
           (cons "file" (%rt-profile-json-scalar (rt-profile-frame-source-file frame)))
           (cons "line" (%rt-profile-json-scalar (rt-profile-frame-source-line frame)))
           (cons "address" (%rt-profile-json-scalar (rt-profile-frame-address frame)))
           (cons "perf_symbol"
                 (%rt-profile-json-scalar (rt-profile-frame-perf-symbol frame)))))))

(defun %rt-profile-sample->json (sample)
  "Build a JSON object describing one profiler SAMPLE with its resolved stack."
  (json-kit:make-json-object
   (list (cons "timeUnixNano" (rt-profile-sample-timestamp-nanos sample))
         (cons "thread_id" (rt-profile-sample-thread-id sample))
         (cons "trace_id" (%rt-profile-json-scalar (rt-profile-sample-trace-id sample)))
         (cons "span_id" (%rt-profile-json-scalar (rt-profile-sample-span-id sample)))
         (cons "count" (rt-profile-sample-count sample))
         (cons "stack" (mapcar #'%rt-profile-frame->json (rt-profile-sample-stack sample))))))

(defun rt-continuous-profile-to-otel-json (session)
  "Export SESSION as thin OpenTelemetry Profiling Signal JSON."
  (let ((samples nil))
    (%rt-profile-with-lock (session)
      (setf samples (coerce (rt-continuous-profile-session-sample-log session) 'list)))
    (let* ((profile
             (json-kit:make-json-object
              (list (cons "profileId" (rt-continuous-profile-session-name session))
                    (cons "trace_id" (rt-continuous-profile-session-trace-id session))
                    (cons "span_id" (rt-continuous-profile-session-span-id session))
                    (cons "name" (rt-continuous-profile-session-name session))
                    (cons "sampleType" "cpu")
                    (cons "periodType" "cpu")
                    (cons "period"
                          (truncate 1000000000
                                    (rt-continuous-profile-session-sample-rate-hz session)))
                    (cons "startTimeUnixNano"
                          (rt-continuous-profile-session-started-at-nanos session))
                    (cons "endTimeUnixNano"
                          (or (rt-continuous-profile-session-stopped-at-nanos session)
                              (%rt-profile-session-now-nanos session)))
                    (cons "samples" (mapcar #'%rt-profile-sample->json samples)))))
           (scope-profile
             (json-kit:make-json-object
              (list (cons "scope"
                          (json-kit:make-json-object (list (cons "name" "cl-cc/runtime"))))
                    (cons "profiles" (list profile)))))
           (resource-profile
             (json-kit:make-json-object
              (list (cons "resource"
                          (json-kit:make-json-object
                           (list (cons "attributes"
                                       (%rt-profile-json-attributes
                                        (rt-continuous-profile-session-attributes session))))))
                    (cons "scopeProfiles" (list scope-profile))))))
      (json-kit:stringify
       (json-kit:make-json-object
        (list (cons "resourceProfiles" (list resource-profile))))))))

(defun rt-continuous-profile-to-pprof-json (session)
  "Export SESSION as a pprof-compatible JSON profile shape.

This JSON mirrors pprof's Profile message concepts (sampleType, sample,
location, function, stringTable) while avoiding a protobuf dependency in the
runtime leaf system."
  (let ((samples nil)
        (function-ids (make-hash-table :test #'equal))
        (location-ids (make-hash-table :test #'equal))
        (string-indices (make-hash-table :test #'equal))
        (string-table (list ""))
        (functions nil)
        (locations nil))
    (setf (gethash "" string-indices) 0)
    (%rt-profile-with-lock (session)
      (setf samples (coerce (rt-continuous-profile-session-sample-log session) 'list)))
    (labels ((string-index (value)
               (let ((text (if (null value) "" (princ-to-string value))))
                 (or (gethash text string-indices)
                     (let ((index (hash-table-count string-indices)))
                       (setf (gethash text string-indices) index)
                       (push text string-table)
                       index))))
             (function-id (frame)
               (let ((key (list (rt-profile-frame-function frame)
                                (rt-profile-frame-source-file frame))))
                 (or (gethash key function-ids)
                     (setf (gethash key function-ids)
                           (let ((id (1+ (hash-table-count function-ids))))
                             (push (json-kit:make-json-object
                                    (list (cons "id" id)
                                          (cons "name"
                                                (string-index
                                                 (rt-profile-frame-function frame)))
                                          (cons "systemName"
                                                (string-index
                                                 (rt-profile-frame-function frame)))
                                          (cons "filename"
                                                (string-index
                                                 (rt-profile-frame-source-file frame)))))
                                   functions)
                             id)))))
             (location-id (frame)
               (let ((key (list (rt-profile-frame-function frame)
                                (rt-profile-frame-source-file frame)
                                (rt-profile-frame-source-line frame)
                                (rt-profile-frame-perf-symbol frame))))
                 (or (gethash key location-ids)
                     (setf (gethash key location-ids)
                           (let* ((id (1+ (hash-table-count location-ids)))
                                  (fid (function-id frame))
                                  (line-json
                                   (json-kit:make-json-object
                                    (list (cons "functionId" fid)
                                          (cons "line"
                                                (%rt-profile-json-scalar
                                                 (rt-profile-frame-source-line frame)))))))
                             (push (json-kit:make-json-object
                                    (list (cons "id" id)
                                          (cons "address"
                                                (%rt-profile-json-scalar
                                                 (rt-profile-frame-address frame)))
                                          (cons "line" (list line-json))
                                          (cons "perfSymbol" (string-index (rt-profile-frame-perf-symbol frame)))))
                                   locations)
                             id))))))
      (let ((sample-json
              (mapcar (lambda (sample)
                        (json-kit:make-json-object
                         (list (cons "locationId"
                                     (mapcar #'location-id
                                             (rt-profile-sample-stack sample)))
                               (cons "value" (list (rt-profile-sample-count sample)))
                               (cons "timeUnixNano"
                                     (rt-profile-sample-timestamp-nanos sample))
                               (cons "threadId" (string-index (rt-profile-sample-thread-id sample)))
                               (cons "traceId" (string-index (rt-profile-sample-trace-id sample)))
                               (cons "spanId" (string-index (rt-profile-sample-span-id sample))))))
                      samples)))
        (json-kit:stringify
         (json-kit:make-json-object
          (list (cons "sampleType"
                      (list (json-kit:make-json-object
                             (list (cons "type" (string-index "samples"))
                                   (cons "unit" (string-index "count")))))
                (cons "periodType"
                      (json-kit:make-json-object
                       (list (cons "type" (string-index "cpu"))
                             (cons "unit" (string-index "nanoseconds")))))
                (cons "period"
                      (truncate 1000000000
                                (rt-continuous-profile-session-sample-rate-hz session)))
                (cons "timeNanos"
                      (rt-continuous-profile-session-started-at-nanos session))
                (cons "durationNanos"
                      (- (or (rt-continuous-profile-session-stopped-at-nanos session)
                             (%rt-profile-session-now-nanos session))
                         (rt-continuous-profile-session-started-at-nanos session)))
                (cons "sample" sample-json)
                (cons "location" (nreverse locations))
                (cons "function" (nreverse functions))
                (cons "stringTable" (nreverse string-table))))))))))

(defun rt-export-continuous-profile
    (session
     &key (format (rt-continuous-profile-session-format session))
          (output (rt-continuous-profile-session-output session)))
  "Export SESSION to FORMAT (:OTEL-JSON or :PPROF-JSON) and OUTPUT.

OUTPUT may be :STDOUT, NIL (return string only), or a pathname/string file.
ENDPOINT is retained on the session for callers that send the returned payload
over HTTP outside this leaf runtime system."
  (let ((payload (ecase format
                   (:otel-json (rt-continuous-profile-to-otel-json session))
                   (:pprof-json (rt-continuous-profile-to-pprof-json session)))))
    (cond
      ((eq output :stdout) (write-line payload *standard-output*))
      ((null output) nil)
      (t (with-open-file (out output :direction :output :if-exists :supersede
                              :if-does-not-exist :create)
           (write-string payload out))))
    payload))

(defun rt-continuous-profile->otel-span (session)
  "Project SESSION samples into a child span with profile.sample events."
  (let ((*rt-otel-span* nil))
    (let* ((parent-context
             (make-instrumentation-context
              :trace-id (rt-continuous-profile-session-trace-id session)
              :span-id (rt-continuous-profile-session-span-id session)
              :trace-flags 1))
           (span (rt-otel-start-span
                  (format nil "continuous-profile:~A"
                          (rt-continuous-profile-session-name session))
                  :parent parent-context)))
      (dolist (attr (rt-continuous-profile-session-attributes session))
        (rt-otel-set-attribute (car attr) (cdr attr) span))
      (%rt-profile-with-lock (session)
        (loop for sample across (rt-continuous-profile-session-sample-log session)
              do (rt-otel-add-event
                  "profile.sample"
                  :attributes
                  (list (cons "thread_id"
                              (rt-profile-sample-thread-id sample))
                        (cons "timestamp_nanos"
                              (rt-profile-sample-timestamp-nanos sample))
                        (cons "stack"
                              (%rt-profile-collapsed-stack
                               (rt-profile-sample-stack sample)))
                        (cons "count" (rt-profile-sample-count sample)))
                  :timestamp-nanos (rt-profile-sample-timestamp-nanos sample)
                  :span span)))
      (rt-otel-end-span span))))
