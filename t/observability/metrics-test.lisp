(progn
  #.(progn (in-package #:cl-cc/runtime/observability/test) nil)

  (defvar *metrics-test-id* 0)

  (defun %metrics-test-name (prefix)
    (format nil "~A_~D" prefix (incf *metrics-test-id*)))

  (it-sequential
    "Counter increment adds N (default 1) and returns the new value."
    (let ((counter (rt-make-counter (%metrics-test-name "reqs"))))
      (expect (rt-counter-increment! counter) :to-equal 1)
      (expect (rt-counter-increment! counter 3) :to-equal 4)
      (expect (rt-counter-value counter) :to-equal 4)))

  (cl-weave:it-property
    "metrics counter value equals sum of increments"
    ((deltas
       (cl-weave:gen-list (cl-weave:gen-integer :min 0 :max 1000)
                          :max-length 10)))
    (let ((counter (rt-make-counter (%metrics-test-name "counter"))))
      (dolist (delta deltas)
        (rt-counter-increment! counter delta))
      (cl-weave:expect
        (rt-counter-value counter)
        :to-be
        (reduce #'+ deltas :initial-value 0))))

  (it-sequential
    "Gauge set stores a value that can rise and fall."
    (let ((gauge (rt-make-gauge (%metrics-test-name "temp"))))
      (rt-gauge-set! gauge 5)
      (expect (rt-gauge-value gauge) :to-equal 5)
      (rt-gauge-set! gauge 2)
      (expect (rt-gauge-value gauge) :to-equal 2)))

  (it-sequential
    "Histogram readers expose bounds and zero values before the first observation."
    (let ((histogram (rt-make-histogram (%metrics-test-name "hist") '(1 5 10))))
      (expect (rt-histogram-buckets histogram)
              :to-equal '(1 5 10))
      (expect (rt-histogram-counts histogram)
              :to-equal '(0 0 0 0))
      (expect (rt-histogram-count histogram) :to-equal 0)
      (expect (rt-histogram-sum histogram) :to-equal 0)))

  (it-sequential
    "Histogram snapshots expose cumulative buckets and the +Inf bucket."
    (let ((histogram (rt-make-histogram (%metrics-test-name "hist") '(1 5 10))))
      (rt-histogram-observe! histogram 0.5)
      (rt-histogram-observe! histogram 3)
      (rt-histogram-observe! histogram 5)
      (expect (rt-histogram-counts histogram)
              :to-equal '(1 3 3 3))))

  (it-sequential
    "An observation above every bound appears in the +Inf bucket."
    (let ((histogram (rt-make-histogram (%metrics-test-name "hist") '(1 5 10))))
      (rt-histogram-observe! histogram 100)
      (expect (rt-histogram-counts histogram)
              :to-equal '(0 0 0 1))))

  (cl-weave:it-property
    "metrics histogram tracks count, sum, and cumulative buckets"
    ((values (cl-weave:gen-list (cl-weave:gen-integer :min 0 :max 20)
                                :min-length 1 :max-length 12)))
    (let ((histogram
            (rt-make-histogram (%metrics-test-name "hist") '(5 10 15))))
      (dolist (value values)
        (rt-histogram-observe! histogram value))
      (cl-weave:expect (rt-histogram-count histogram)
                       :to-be (length values))
      (cl-weave:expect (rt-histogram-sum histogram)
                       :to-be (reduce #'+ values))
      (cl-weave:expect
        (car (last (rt-histogram-counts histogram)))
        :to-be
        (length values))))

  (it-sequential
    "A bare counter renders with the kit Prometheus type and value lines."
    (let* ((name (%metrics-test-name "http_requests"))
           (text (prometheus-text-format (list (rt-make-counter name)))))
      (expect (search (format nil "# TYPE ~A counter" name) text) :to-be-truthy)
      (expect (search (format nil "~A 0" name) text) :to-be-truthy)))

  (it-sequential
    "Label keys are normalized in the rendered output."
    (let* ((counter
             (rt-make-counter (%metrics-test-name "reqs")
                              :labels '(:METHOD "GET")))
           (text (prometheus-text-format (list counter))))
      (expect (search (format nil "method=~CGET~C" #\" #\") text)
              :to-be-truthy)))

  (it-sequential
    "Histogram rendering includes cumulative le buckets, +Inf, _sum, and _count."
    (let* ((name (%metrics-test-name "lat"))
           (histogram (rt-make-histogram name '(1 5))))
      (rt-histogram-observe! histogram 3)
      (let ((text (prometheus-text-format (list histogram))))
        (expect (search (format nil "# TYPE ~A histogram" name) text)
                :to-be-truthy)
        (expect (search (format nil "~A_bucket{le=~C+Inf~C} 1"
                                name #\" #\")
                        text)
                :to-be-truthy)
        (expect (search (format nil "~A_count 1" name) text)
                :to-be-truthy))))

  (it-sequential
    "A gauge renders with the kit Prometheus type and value lines."
    (let* ((name (%metrics-test-name "queue_depth"))
           (gauge (rt-make-gauge name)))
      (rt-gauge-set! gauge 7)
      (let ((text (prometheus-text-format (list gauge))))
        (expect (search (format nil "# TYPE ~A gauge" name) text)
                :to-be-truthy)
        (expect (search (format nil "~A 7" name) text)
                :to-be-truthy))))

  (it-sequential
    "Registered metrics appear when formatting the whole kit registry."
    (let* ((name (%metrics-test-name "registered_total"))
           (counter (rt-make-counter name)))
      (rt-counter-increment! counter 5)
      (rt-register-metric counter)
      (let ((text (with-output-to-string (stream)
                    (rt-metrics-format-prometheus stream))))
        (expect (search (format nil "~A 5" name) text) :to-be-truthy))))

  (it-sequential
    "gc-stats returns a plist exposing the stable public GC fields."
    (let ((stats (cl-cc/runtime/observability:gc-stats)))
      (expect (listp stats) :to-be-truthy)
      (expect (member :minor-gcs stats) :to-be-truthy)
      (expect (member :major-gcs stats) :to-be-truthy))))

(in-package :cl-cc/runtime/observability/test)

(it-sequential
  "FR-356: public gc-stats exposes stable GC counters and byte/pause metrics."
  (let* ((heap (cl-cc/runtime/memory:make-rt-heap :young-size 32 :old-size 32))
         (stats (cl-cc/runtime/observability:gc-stats heap)))
    (expect (member :minor-gcs stats) :to-be-truthy)
    (expect (member :major-gcs stats) :to-be-truthy)
    (expect (member :total-collected-bytes stats) :to-be-truthy)
    (expect (member :pause-ms-p99 stats) :to-be-truthy)
    (expect (getf stats :minor-gcs) :to-equal 0)
    (expect (getf stats :major-gcs) :to-equal 0)
    (expect (getf stats :total-collected-bytes) :to-equal 0)))
