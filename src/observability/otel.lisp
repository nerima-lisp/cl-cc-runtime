(progn
  #.(progn (in-package #:cl-cc/runtime/observability) nil)

  (defconstant +rt-otel-universal-time-offset+ 2208988800)
  (defconstant +rt-otel-nanoseconds-per-second+ 1000000000)

  (defstruct rt-otel-event
    (name "")
    (time 0)
    (attributes nil))

  (defstruct (rt-otel-span (:constructor %make-rt-otel-span (handle)))
    handle
    record
    name
    trace-id
    span-id
    parent-span-id
    start
    end
    (attributes (make-hash-table :test (function equal)))
    events
    status-code
    status-message)

  (defvar *rt-otel-span* nil)
  (defvar *rt-otel-ending-span* nil)

  (defun %rt-otel-random-hex (bytes)
    (with-output-to-string (out)
      (dotimes (i bytes)
        (format out "~2,'0X" (random 256)))))

  (defun %rt-otel-time->unix-nanos (time)
    (truncate (* (- time +rt-otel-universal-time-offset+)
                 +rt-otel-nanoseconds-per-second+)))

  (defun %rt-otel-unix-nanos->time (nanos)
    (+ +rt-otel-universal-time-offset+
       (/ nanos +rt-otel-nanoseconds-per-second+)))

  (defun %rt-otel-now-nanos ()
    (%rt-otel-time->unix-nanos (get-universal-time)))

  (defun %rt-otel-attributes-alist (attributes)
    (cond
      ((null attributes) nil)
      ((hash-table-p attributes)
       (let ((pairs nil))
         (maphash (lambda (key value)
                    (push (cons (princ-to-string key) value) pairs))
                  attributes)
         (nreverse pairs)))
      ((and (listp attributes) (every #'consp attributes))
       (mapcar (lambda (pair)
                 (cons (princ-to-string (car pair)) (cdr pair)))
               attributes))
      ((and (listp attributes) (evenp (length attributes)))
       (loop for (key value) on attributes by #'cddr
             collect (cons (princ-to-string key) value)))
      (t
       (error "OpenTelemetry attributes must be a hash table, alist, or property list."))))

  (defun %rt-json-scalar (value)
    "Coerce VALUE to a cl-json-kit-serializable scalar with OTLP null/true semantics."
    (cond
      ((null value) json-kit:+json-null+)
      ((eq value t) t)
      ((numberp value) value)
      ((stringp value) value)
      (t (princ-to-string value))))

  (defun %rt-json-attributes (attributes)
    "Build a JSON object from hash tables, flat alists, or OTLP attribute documents."
    (let ((members nil))
      (cond
       ((hash-table-p attributes)
        (maphash (lambda (key value)
                   (push (cons (princ-to-string key) (%rt-json-scalar value))
                         members))
                 attributes))
       ((and (proper-list-p attributes)
             (every (lambda (attribute)
                      (and (proper-list-p attribute)
                           (every (function consp) attribute)
                           (assoc "key" attribute :test (function string=))
                           (assoc "value" attribute :test (function string=))))
                    attributes))
        (dolist (attribute attributes)
          (let ((key (assoc "key" attribute :test (function string=)))
                (value (assoc "value" attribute :test (function string=))))
            (push (cons (princ-to-string (cdr key))
                        (%rt-json-scalar (cdr value)))
                  members))))
       (t
        (dolist (pair attributes)
          (push (cons (princ-to-string (car pair))
                      (%rt-json-scalar (cdr pair)))
                members))))
      (json-kit:make-json-object (nreverse members))))

;; 
  (defun %rt-otel-id-generator (trace-id span-id)
    (let ((pending-trace-id trace-id)
          (pending-span-id span-id))
      (lambda (length)
        (case length
          (32 (prog1 (or pending-trace-id (%rt-otel-random-hex 16))
                (setf pending-trace-id nil)))
          (16 (prog1 (or pending-span-id (%rt-otel-random-hex 8))
                (setf pending-span-id nil)))
          (otherwise
           (error "Unexpected trace identifier length: ~D" length))))))

  (defun %rt-otel-capture-span-record (record)
    (let ((span *rt-otel-ending-span*))
      (when (and span
                 (string= (span-id (rt-otel-span-handle span))
                          (span-record-span-id record)))
        (setf (rt-otel-span-record span) record)))
    nil)

  (defvar *rt-otel-tracer-provider*
    (make-tracer-provider :exporter #'%rt-otel-capture-span-record))

  (defvar *rt-otel-tracer*
    (make-tracer *rt-otel-tracer-provider* "cl-cc/runtime"))

  (defun %rt-otel-span-handle (span)
    (check-type span rt-otel-span)
    (rt-otel-span-handle span))

  (defun %rt-otel-event-from-kit (event)
    (make-rt-otel-event
     :name (span-event-name event)
     :time (%rt-otel-time->unix-nanos (span-event-timestamp event))
     :attributes (span-event-attributes event)))
  (defun %rt-otel-populate-span (span &optional events)
    (let* ((handle (%rt-otel-span-handle span))
           (attributes (make-hash-table :test (function equal)))
           (start-time (span-start-time handle))
           (end-time (span-end-time handle)))
      (dolist (pair (span-attributes handle))
        (setf (gethash (car pair) attributes) (cdr pair)))
      (setf (rt-otel-span-name span) (span-name handle)
            (rt-otel-span-trace-id span) (span-trace-id handle)
            (rt-otel-span-span-id span) (span-id handle)
            (rt-otel-span-parent-span-id span) (span-parent-span-id handle)
            (rt-otel-span-start span) (%rt-otel-time->unix-nanos start-time)
            (rt-otel-span-end span)
            (if end-time (%rt-otel-time->unix-nanos end-time) 0)
            (rt-otel-span-attributes span) attributes
            (rt-otel-span-events span)
            (or events
                (mapcar (function %rt-otel-event-from-kit)
                        (span-events handle)))
            (rt-otel-span-status-code span)
            (string-upcase (symbol-name (span-status handle)))
            (rt-otel-span-status-message span)
            (or (span-status-message handle) ""))
      span))

  (defun make-rt-otel-span (&key (name "span") trace-id span-id parent-span-id
                                 (start nil start-supplied-p)
                                 (end nil end-supplied-p)
                                 attributes events
                                 (status-code "UNSET")
                                 (status-message ""))
    (let* ((parent-context
             (when parent-span-id
               (make-instrumentation-context
                :trace-id (or trace-id (%rt-otel-random-hex 16))
                :span-id parent-span-id
                :trace-flags 1)))
           (custom-ids-p (or trace-id span-id))
           (provider
             (if custom-ids-p
                 (make-tracer-provider
                  :id-generator (%rt-otel-id-generator trace-id span-id)
                  :exporter (function %rt-otel-capture-span-record))
                 *rt-otel-tracer-provider*))
           (tracer (if custom-ids-p
                       (make-tracer provider "cl-cc/runtime")
                       *rt-otel-tracer*))
           (options (list :parent parent-context
                          :attributes (%rt-otel-attributes-alist attributes))))
      (when start-supplied-p
        (setf options
              (append options
                      (list :start-time (%rt-otel-unix-nanos->time start)))))
      (let* ((handle (apply (function start-span) tracer name options))
             (span (%make-rt-otel-span handle)))
        (dolist (event events)
          (check-type event rt-otel-event)
          (span-add-event
           handle
           (rt-otel-event-name event)
           :attributes (%rt-otel-attributes-alist
                        (rt-otel-event-attributes event))
           :timestamp (%rt-otel-unix-nanos->time
                       (rt-otel-event-time event))))
        (unless (and (string= (string-upcase (princ-to-string status-code))
                              "UNSET")
                     (equal status-message ""))
          (span-set-status
           handle
           (intern (string-upcase (string status-code)) :keyword)
           :message status-message))
        (%rt-otel-populate-span span events)
        (when start-supplied-p
          (setf (rt-otel-span-start span) start))
        (when end-supplied-p
          (let ((*rt-otel-ending-span* span))
            (end-span handle
                      :end-time (%rt-otel-unix-nanos->time end))
            (setf (rt-otel-span-end span) end
                  (rt-otel-span-record span)
                  (or (rt-otel-span-record span)
                      (error "The tracing kit did not produce a span record.")))))
        span)))

  (defun rt-otel-start-span (name &key parent)
    (let* ((parent-handle (if (rt-otel-span-p parent)
                              (%rt-otel-span-handle parent)
                              parent))
           (handle (start-span *rt-otel-tracer* name :parent parent-handle))
           (span (%make-rt-otel-span handle)))
      (%rt-otel-populate-span span)
      (setf *rt-otel-span* span)
      span))

  (defun %rt-otel-finish-span (span end-time)
    (let ((handle (%rt-otel-span-handle span)))
      (let ((*rt-otel-ending-span* span))
        (if end-time
            (end-span handle :end-time end-time)
            (end-span handle)))
      (let ((span-end (span-end-time handle)))
        (setf (rt-otel-span-end span)
              (if span-end (%rt-otel-time->unix-nanos span-end) 0))))
    (when (eq *rt-otel-span* span)
      (setf *rt-otel-span* nil))
    span)

  (defun rt-otel-end-span (span)
    (%rt-otel-finish-span span nil))

  (defun rt-otel-set-attribute (key value &optional (span *rt-otel-span*))
    (unless span
      (error "No active OpenTelemetry span"))
    (let ((attribute-key (princ-to-string key)))
      (span-set-attribute (%rt-otel-span-handle span)
                          attribute-key
                          value)
      (setf (gethash attribute-key (rt-otel-span-attributes span)) value))
    value)

  (defun rt-otel-add-event
      (name &key attributes (timestamp-nanos nil timestamp-nanos-p)
                  (span *rt-otel-span*))
    (unless span
      (error "No active OpenTelemetry span"))
    (let* ((handle (%rt-otel-span-handle span))
           (options (list :attributes (%rt-otel-attributes-alist attributes))))
      (when timestamp-nanos-p
        (setf options
              (append options
                      (list :timestamp
                            (%rt-otel-unix-nanos->time timestamp-nanos)))))
      (apply #'span-add-event handle name options)
      (let ((event (%rt-otel-event-from-kit
                    (car (last (span-events handle))))))
        (setf (rt-otel-span-events span)
              (append (rt-otel-span-events span) (list event)))
        event)))

  (defun rt-otel-set-status (status &optional (message "") (span *rt-otel-span*))
    (unless span
      (error "No active OpenTelemetry span"))
    (let* ((code (string-upcase (string status)))
           (status-keyword (intern code :keyword)))
      (span-set-status (%rt-otel-span-handle span)
                       status-keyword
                       :message message)
      (setf (rt-otel-span-status-code span) code
            (rt-otel-span-status-message span) message)
      code))

  (defun %rt-otel-field (document name)
    (cdr (assoc name document :test #'string=)))

  (defun %rt-otel-event-document->json (event)
    (json-kit:make-json-object
     (list (cons "name" (rt-otel-event-name event))
           (cons "timeUnixNano"
                 (%rt-json-scalar (rt-otel-event-time event)))
           (cons "attributes"
                 (%rt-json-attributes
                  (rt-otel-event-attributes event))))))

  (defun %rt-otel-record->json (span)
    (let* ((record (rt-otel-span-record span))
           (document (when record (span-record->otlp record)))
           (kind (or (%rt-otel-field document "kind") "internal"))
           (status
             (json-kit:make-json-object
              (list (cons "code"
                          (string-upcase
                           (princ-to-string
                            (rt-otel-span-status-code span))))
                    (cons "message"
                          (or (rt-otel-span-status-message span) ""))))))
      (json-kit:stringify
       (json-kit:make-json-object
        (list (cons "traceId"
                    (%rt-json-scalar (rt-otel-span-trace-id span)))
              (cons "spanId"
                    (%rt-json-scalar (rt-otel-span-span-id span)))
              (cons "parentSpanId"
                    (or (rt-otel-span-parent-span-id span) ""))
              (cons "name" (rt-otel-span-name span))
              (cons "kind" (format nil "SPAN_KIND_~A" kind))
              (cons "startTimeUnixNano"
                    (%rt-json-scalar (rt-otel-span-start span)))
              (cons "endTimeUnixNano"
                    (%rt-json-scalar (rt-otel-span-end span)))
              (cons "attributes"
                    (%rt-json-attributes (rt-otel-span-attributes span)))
              (cons "events"
                    (mapcar (function %rt-otel-event-document->json)
                            (rt-otel-span-events span)))
              (cons "status" status))))))

  (defun rt-otel-span-to-json (span)
    (%rt-otel-record->json span))

  (defun rt-otel-init ()
    (setf *rt-otel-span* nil)
    t)

  (defmacro rt-with-span ((name &key attrs) &body body)
    (let ((span-var (gensym "SPAN")))
      (list 'let
            (list (list '*rt-otel-span* '*rt-otel-span*))
            (list 'let
                  (list (list span-var
                              (list 'rt-otel-start-span name
                                    :parent '*rt-otel-span*)))
                  (list 'dolist
                        (list 'attr (list 'quote attrs))
                        (list 'rt-otel-set-attribute
                              (list 'car 'attr)
                              (list 'cdr 'attr)
                              span-var))
                  (list 'unwind-protect
                        (cons 'progn body)
                        (list 'rt-otel-end-span span-var)))))))

