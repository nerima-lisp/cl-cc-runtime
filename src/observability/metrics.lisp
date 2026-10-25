;;; ─── Phase 139 Runtime Metrics ───
;;; FR-792: Prometheus-compatible counter/histogram/gauge metrics

(progn
  #.(progn (in-package #:cl-cc/runtime/observability) nil)

  (defvar *rt-meter-provider* (make-meter-provider))
  (defvar *rt-meter* (make-meter *rt-meter-provider* "cl-cc/runtime"))
  (defvar *rt-metrics-registry* (meter-registry *rt-meter*))

  (defstruct (rt-counter (:constructor %make-rt-counter (name labels metric)))
    name
    labels
    metric)

  (defstruct (rt-gauge (:constructor %make-rt-gauge (name metric)))
    name
    metric)

  (defstruct (rt-histogram (:constructor %make-rt-histogram (name metric)))
    name
    metric)

  (defun %rt-metric-label-pairs (labels)
    (cond
      ((null labels) nil)
      ((and (proper-list-p labels) (every #'consp labels)) labels)
      ((proper-list-p labels)
       (unless (evenp (length labels))
         (error "Metric labels must be an alist or an even property list."))
       (loop for (name value) on labels by #'cddr
             collect (cons name value)))
      (t
       (error "Metric labels must be an alist or property list."))))

  (defun %rt-metric-label-names (labels)
    (mapcar (lambda (pair)
              (string-downcase (string (car pair))))
            (%rt-metric-label-pairs labels)))

  ;; The kit declaration macros require a source-level symbol.  MAKE-SYMBOL
  ;; carries the runtime name as data; EVAL expands the fixed macro form.
  (defun %rt-define-kit-metric (kind name &key labels buckets)
    (let* ((metric-name-symbol
             (make-symbol (string-downcase (string name))))
           (declaration
             (ecase kind
               (:counter
                (append (list 'define-counter '*rt-meter* metric-name-symbol)
                        (when labels
                          (list :label-names
                                (list 'quote (%rt-metric-label-names labels))))))
               (:gauge
                (list 'define-gauge '*rt-meter* metric-name-symbol))
               (:histogram
                (append (list 'define-histogram '*rt-meter* metric-name-symbol)
                        (when buckets
                          (list :buckets (list 'quote buckets))))))))
      (eval declaration)))

  (defun %rt-metric-samples (metric)
    (metric-snapshot-samples (metric-snapshot metric)))

  (defun %rt-metric-value (metric)
    (let ((sample (first (%rt-metric-samples metric))))
      (if sample (metric-sample-value sample) 0)))

  (defun rt-make-counter (name &key labels)
    (let* ((metric (%rt-define-kit-metric :counter name :labels labels))
           (counter (%make-rt-counter (metric-name metric) labels metric)))
      (when labels
        (metric-inc metric 0 :labels labels))
      counter))

  (defun rt-counter-increment! (counter &optional (n 1))
    (let ((metric (rt-counter-metric counter))
          (labels (rt-counter-labels counter)))
      (if labels
          (metric-inc metric n :labels labels)
          (metric-inc metric n))))

  (defun rt-counter-value (counter)
    (%rt-metric-value (rt-counter-metric counter)))

  (defun rt-make-gauge (name)
    (let ((metric (%rt-define-kit-metric :gauge name)))
      (%make-rt-gauge (metric-name metric) metric)))

  (defun rt-gauge-set! (gauge value)
    (metric-set (rt-gauge-metric gauge) value))

  (defun rt-gauge-value (gauge)
    (%rt-metric-value (rt-gauge-metric gauge)))

  (defun rt-make-histogram (name &rest args)
    (let ((buckets
            (cond
              ((and args (keywordp (first args)))
               (unless (and (eq (first args) :buckets)
                            (= (length args) 2))
                 (error "Invalid rt-make-histogram arguments: ~S" args))
               (second args))
              ((<= (length args) 1)
               (first args))
              (t
               (error "Invalid rt-make-histogram arguments: ~S" args)))))
      (let ((metric (%rt-define-kit-metric :histogram name :buckets buckets)))
        (%make-rt-histogram (metric-name metric) metric))))

  (defun %rt-histogram-sample (histogram)
    (first (%rt-metric-samples (rt-histogram-metric histogram))))

  (defun rt-histogram-observe! (histogram value)
    (metric-observe (rt-histogram-metric histogram) value))

  (defun rt-histogram-buckets (histogram)
    (let ((sample (%rt-histogram-sample histogram)))
      (when sample
        (mapcar #'car (butlast (metric-sample-buckets sample))))))

  (defun rt-histogram-counts (histogram)
    (let ((sample (%rt-histogram-sample histogram)))
      (when sample
        (mapcar #'cdr (metric-sample-buckets sample)))))

  (defun rt-histogram-count (histogram)
    (let ((sample (%rt-histogram-sample histogram)))
      (if sample
          (or (metric-sample-count sample) 0)
          0)))

  (defun rt-histogram-sum (histogram)
    (let ((sample (%rt-histogram-sample histogram)))
      (if sample
          (or (metric-sample-sum sample) 0)
          0)))

  (defun %rt-kit-metric (metric)
    (typecase metric
      (rt-counter (rt-counter-metric metric))
      (rt-gauge (rt-gauge-metric metric))
      (rt-histogram (rt-histogram-metric metric))
      (t
       (error "Cannot register unsupported runtime metric: ~S" metric))))

  (defun rt-register-metric (metric)
    (%rt-kit-metric metric)
    metric)

  (defun rt-metrics-format-prometheus (&optional (stream *standard-output*))
    (render-prometheus *rt-metrics-registry* :stream stream))

  (defun prometheus-text-format (metrics)
    (render-prometheus
     (mapcar (lambda (metric)
               (metric-snapshot (%rt-kit-metric metric)))
             metrics))))

(defun gc-stats (&optional heap)
  "Return the public GC statistics plist.

When HEAP is NIL, use the current runtime heap if one is bound; otherwise
return a fresh empty heap snapshot."
  (if heap
      (rt-gc-stats heap)
      (rt-gc-current-stats)))
