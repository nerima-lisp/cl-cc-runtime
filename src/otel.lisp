(in-package :cl-cc/runtime)

(defstruct rt-otel-event
  (name "")
  (time 0)
  (attributes nil))

(defstruct rt-otel-span
  (name "")
  (trace-id nil)
  (span-id nil)
  (parent-span-id nil)
  (start 0)
  (end 0)
  (attributes (make-hash-table :test #'equal))
  (events nil)
  (status-code "UNSET")
  (status-message ""))

(defvar *rt-otel-span* nil)

(defun %rt-otel-random-hex (bytes)
  (with-output-to-string (out)
    (dotimes (i bytes)
      (format out "~2,'0X" (random 256)))))

(defun %rt-otel-now-nanos ()
  (* (get-universal-time) 1000000000))

(defun %rt-json-scalar (value)
  "Coerce VALUE to a cl-json-kit-serializable scalar with OTLP null/true semantics."
  (cond
    ((null value) json-kit:+json-null+)
    ((eq value t) t)
    ((numberp value) value)
    ((stringp value) value)
    (t (princ-to-string value))))

(defun %rt-json-attributes (attributes)
  "Build an ordered JSON object from ATTRIBUTES, a hash-table or an alist."
  (let ((members nil))
    (if (hash-table-p attributes)
        (maphash (lambda (key value)
                   (push (cons (princ-to-string key) (%rt-json-scalar value)) members))
                 attributes)
        (dolist (pair attributes)
          (push (cons (princ-to-string (car pair)) (%rt-json-scalar (cdr pair))) members)))
    (json-kit:make-json-object (nreverse members))))

(defun %rt-otel-events->json (events)
  "Return EVENTS (stored newest-first) as a chronologically ordered JSON array."
  (mapcar (lambda (event)
            (json-kit:make-json-object
             (list (cons "name" (rt-otel-event-name event))
                   (cons "timeUnixNano" (rt-otel-event-time event))
                   (cons "attributes" (%rt-json-attributes (rt-otel-event-attributes event))))))
          (reverse events)))

(defun rt-otel-start-span (name &key parent)
  (let ((span (make-rt-otel-span
               :name name
               :trace-id (or (when parent (rt-otel-span-trace-id parent))
                             (%rt-otel-random-hex 16))
               :span-id (%rt-otel-random-hex 8)
               :parent-span-id (when parent (rt-otel-span-span-id parent))
               :start (%rt-otel-now-nanos))))
    (setf *rt-otel-span* span)
    span))

(defun rt-otel-end-span (span)
  (setf (rt-otel-span-end span) (%rt-otel-now-nanos))
  (when (eq *rt-otel-span* span)
    (setf *rt-otel-span* nil))
  span)

(defun rt-otel-set-attribute (key value &optional (span *rt-otel-span*))
  "Set an OpenTelemetry attribute on SPAN or the current span."
  (unless span
    (error "No active OpenTelemetry span"))
  (setf (gethash (princ-to-string key) (rt-otel-span-attributes span)) value)
  value)

(defun rt-otel-add-event (name &key attributes (span *rt-otel-span*))
  "Add a timestamped event to SPAN or the current span."
  (unless span
    (error "No active OpenTelemetry span"))
  (let ((event (make-rt-otel-event
                :name name
                :time (%rt-otel-now-nanos)
                :attributes (or attributes nil))))
    (push event (rt-otel-span-events span))
    event))

(defun rt-otel-set-status (status &optional (message "") (span *rt-otel-span*))
  "Set SPAN status to OK, ERROR, or UNSET."
  (unless span
    (error "No active OpenTelemetry span"))
  (let ((code (string-upcase (princ-to-string status))))
    (unless (member code '("OK" "ERROR" "UNSET") :test #'string=)
      (error "Invalid OpenTelemetry status: ~a" status))
    (setf (rt-otel-span-status-code span) code
          (rt-otel-span-status-message span) (princ-to-string message))
    code))

(defun rt-otel-span-to-json (span)
  "Export SPAN as an OTLP-compatible JSON span object."
  (json-kit:stringify
   (json-kit:make-json-object
    (list (cons "traceId" (rt-otel-span-trace-id span))
          (cons "spanId" (rt-otel-span-span-id span))
          (cons "parentSpanId" (or (rt-otel-span-parent-span-id span) ""))
          (cons "name" (rt-otel-span-name span))
          (cons "kind" "SPAN_KIND_INTERNAL")
          (cons "startTimeUnixNano" (rt-otel-span-start span))
          (cons "endTimeUnixNano" (rt-otel-span-end span))
          (cons "attributes" (%rt-json-attributes (rt-otel-span-attributes span)))
          (cons "events" (%rt-otel-events->json (rt-otel-span-events span)))
          (cons "status"
                (json-kit:make-json-object
                 (list (cons "code" (rt-otel-span-status-code span))
                       (cons "message" (rt-otel-span-status-message span)))))))))

(defmacro rt-with-span ((name &key attrs) &body body)
  (let ((span-var (gensym "SPAN")))
    `(let ((,span-var (rt-otel-start-span ,name)))
       (dolist (attr ',attrs)
         (rt-otel-set-attribute (car attr) (cdr attr) ,span-var))
       (unwind-protect
            (progn ,@body)
         (rt-otel-end-span ,span-var)))))

(defun rt-otel-init ()
  (setf *rt-otel-span* nil)
  t)

