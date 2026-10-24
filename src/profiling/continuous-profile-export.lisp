;;;; packages/runtime/src/continuous-profile-export.lisp — FR-701 continuous
;;;; profile export: JSON, OTel profiles signal, and pprof-JSON encodings

(in-package :cl-cc/runtime)

(defun %rt-profile-frame->json (frame)
  "Build a JSON object describing one resolved profile FRAME."
  (json-kit:make-json-object
   (list (cons "function" (rt-profile-frame-function frame))
         (cons "file" (%rt-json-scalar (rt-profile-frame-source-file frame)))
         (cons "line" (%rt-json-scalar (rt-profile-frame-source-line frame)))
         (cons "address" (%rt-json-scalar (rt-profile-frame-address frame)))
         (cons "perf_symbol" (%rt-json-scalar (rt-profile-frame-perf-symbol frame))))))

(defun %rt-profile-sample->json (sample)
  "Build a JSON object describing one profiler SAMPLE with its resolved stack."
  (json-kit:make-json-object
   (list (cons "timeUnixNano" (rt-profile-sample-timestamp-nanos sample))
         (cons "thread_id" (rt-profile-sample-thread-id sample))
         (cons "trace_id" (%rt-json-scalar (rt-profile-sample-trace-id sample)))
         (cons "span_id" (%rt-json-scalar (rt-profile-sample-span-id sample)))
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
                              (%rt-profile-now-nanos)))
                    (cons "samples" (mapcar #'%rt-profile-sample->json samples)))))
           (scope-profile
             (json-kit:make-json-object
              (list (cons "scope" (json-kit:make-json-object (list (cons "name" "cl-cc/runtime"))))
                    (cons "profiles" (list profile)))))
           (resource-profile
             (json-kit:make-json-object
              (list (cons "resource"
                          (json-kit:make-json-object
                           (list (cons "attributes"
                                       (%rt-json-attributes
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
        (functions nil)
        (locations nil))
    (%rt-profile-with-lock (session)
      (setf samples (coerce (rt-continuous-profile-session-sample-log session) 'list)))
    (labels ((function-id (frame)
               (let ((key (list (rt-profile-frame-function frame)
                                (rt-profile-frame-source-file frame))))
                 (or (gethash key function-ids)
                     (setf (gethash key function-ids)
                           (let ((id (1+ (hash-table-count function-ids))))
                             (push (json-kit:make-json-object
                                    (list (cons "id" id)
                                          (cons "name" (rt-profile-frame-function frame))
                                          (cons "filename"
                                                (%rt-json-scalar
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
                                                (%rt-json-scalar
                                                 (rt-profile-frame-source-line frame)))))))
                             (push (json-kit:make-json-object
                                    (list (cons "id" id)
                                          (cons "address"
                                                (%rt-json-scalar
                                                 (rt-profile-frame-address frame)))
                                          (cons "line" (list line-json))
                                          (cons "perfSymbol"
                                                (%rt-json-scalar
                                                 (rt-profile-frame-perf-symbol frame)))))
                                   locations)
                             id))))))
      (let ((sample-json
              (mapcar (lambda (sample)
                        (json-kit:make-json-object
                         (list (cons "locationId"
                                     (mapcar #'location-id (rt-profile-sample-stack sample)))
                               (cons "value" (list (rt-profile-sample-count sample)))
                               (cons "timeUnixNano" (rt-profile-sample-timestamp-nanos sample))
                               (cons "threadId" (rt-profile-sample-thread-id sample))
                               (cons "traceId"
                                     (%rt-json-scalar (rt-profile-sample-trace-id sample)))
                               (cons "spanId"
                                     (%rt-json-scalar (rt-profile-sample-span-id sample))))))
                      samples)))
        (json-kit:stringify
         (json-kit:make-json-object
          (list (cons "sampleType"
                      (list (json-kit:make-json-object
                             (list (cons "type" "samples") (cons "unit" "count")))))
                (cons "periodType"
                      (json-kit:make-json-object
                       (list (cons "type" "cpu") (cons "unit" "nanoseconds"))))
                (cons "period" (truncate 1000000000
                                         (rt-continuous-profile-session-sample-rate-hz session)))
                (cons "timeNanos" (rt-continuous-profile-session-started-at-nanos session))
                (cons "durationNanos"
                      (- (or (rt-continuous-profile-session-stopped-at-nanos session)
                             (%rt-profile-now-nanos))
                         (rt-continuous-profile-session-started-at-nanos session)))
                (cons "sample" sample-json)
                (cons "location" (nreverse locations))
                (cons "function" (nreverse functions))
                (cons "stringTable" (list "")))))))))

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
  "Export SESSION as an OpenTelemetry-compatible span with sample events."
  (let ((span (rt-otel-start-span (format nil "continuous-profile:~A"
                                          (rt-continuous-profile-session-name session)))))
    (setf (rt-otel-span-trace-id span) (rt-continuous-profile-session-trace-id session)
          (rt-otel-span-span-id span) (rt-continuous-profile-session-span-id session))
    (dolist (attr (rt-continuous-profile-session-attributes session))
      (rt-otel-set-attribute (car attr) (cdr attr) span))
    (%rt-profile-with-lock (session)
      (loop for sample across (rt-continuous-profile-session-sample-log session)
            do (rt-otel-add-event "profile.sample"
                                  :attributes
                                  `(("thread_id" . ,(rt-profile-sample-thread-id sample))
                                    ("timestamp_nanos"
                                     . ,(rt-profile-sample-timestamp-nanos sample))
                                    ("stack" . ,(%rt-profile-collapsed-stack
                                                 (rt-profile-sample-stack sample)))
                                    ("count" . ,(rt-profile-sample-count sample)))
                                  :span span)))
    (rt-otel-end-span span)))
