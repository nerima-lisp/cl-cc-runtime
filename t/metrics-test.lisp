(in-package :cl-cc-runtime/test)

;;;; Tests for src/metrics.lisp — FR-792 Prometheus-compatible metrics.
;;;;
;;;; Covers counter/gauge/histogram data structures, the non-cumulative bucket
;;;; assignment used by rt-histogram-observe!, and both Prometheus text emitters.
;;;; Metric struct accessors are unexported (cl-cc/runtime:: below); the global
;;;; registry is cleared before the tests that iterate it.
;;; ── Counter ───────────────────────────────────────────────────────
(it-sequential
  "Counter increment adds N (default 1) and returns the new value."
  (let ((c (rt-make-counter "reqs")))
    (expect (rt-counter-increment! c) :to-equal 1)
    (expect (rt-counter-increment! c 3) :to-equal 4)
    (expect (cl-cc/runtime::rt-counter-value c) :to-equal 4)))

(cl-weave:it-property
  "metrics counter value equals sum of increments"
  ((deltas
      (cl-weave:gen-list (cl-weave:gen-integer :min 0 :max 1000) :max-length 10)))
  (let ((c (rt-make-counter "p")))
    (dolist (d deltas)
      (rt-counter-increment! c d))
    (cl-weave:expect
      (cl-cc/runtime::rt-counter-value c)
      :to-be
      (reduce #'+ deltas :initial-value 0))))

;;; ── Gauge ─────────────────────────────────────────────────────────
(it-sequential
  "Gauge set stores a double-float value that can rise and fall."
  (let ((g (rt-make-gauge "temp")))
    (rt-gauge-set! g 5)
    (expect (cl-cc/runtime::rt-gauge-value g) :to-equal 5d0)
    (rt-gauge-set! g 2)
    (expect (cl-cc/runtime::rt-gauge-value g) :to-equal 2d0)))

;;; ── Histogram ─────────────────────────────────────────────────────
(it-sequential
  "Buckets are stored in ascending order regardless of input order."
  (let ((h (rt-make-histogram "h" '(10 1 5))))
    (expect (cl-cc/runtime::rt-histogram-buckets h) :to-equal '(1 5 10))))

(it-sequential "Each observation lands in the first bucket whose bound it does not exceed." (let ((h (rt-make-histogram "h" '(1 5 10))))
    (rt-histogram-observe! h 0.5)   ; -> bucket 0 (<=1)
    (rt-histogram-observe! h 3)     ; -> bucket 1 (<=5)
    (rt-histogram-observe! h 5)     ; -> bucket 1 (<=5)
    (expect (cl-cc/runtime::rt-histogram-counts h) :to-equal '(1 2 0))))

(it-sequential
  "A value above every bound is counted in the final bucket."
  (let ((h (rt-make-histogram "h" '(1 5 10))))
    (rt-histogram-observe! h 100)
    (expect (cl-cc/runtime::rt-histogram-counts h) :to-equal '(0 0 1))))

(cl-weave:it-property "metrics histogram tracks count and sum"
    ((values (cl-weave:gen-list (cl-weave:gen-integer :min 0 :max 20)
                                :min-length 1 :max-length 12)))
  (let ((h (rt-make-histogram "h" '(5 10 15))))
    (dolist (v values) (rt-histogram-observe! h v))
    (cl-weave:expect (cl-cc/runtime::rt-histogram-count h)
                     :to-be (length values))
    (cl-weave:expect (cl-cc/runtime::rt-histogram-sum h)
                     :to-be (float (reduce #'+ values) 1d0))
    ;; every observation is counted in exactly one bucket
    (cl-weave:expect (reduce #'+ (cl-cc/runtime::rt-histogram-counts h))
                     :to-be (length values))))

;;; ── Prometheus text format ────────────────────────────────────────
(it-sequential
  "A bare counter renders a TYPE comment and a name/value line."
  (let ((text (prometheus-text-format (list (rt-make-counter "http_requests")))))
    (expect (search "# TYPE http_requests counter" text) :to-be-truthy)
    (expect (search "http_requests 0" text) :to-be-truthy)))

(it-sequential
  "Label keys are normalized to lowercase in the rendered output."
  (let* ((c (rt-make-counter "reqs" :labels '(:METHOD "GET")))
         (text (prometheus-text-format (list c))))
    (expect (search "method=\"GET\"" text) :to-be-truthy)))

(it-sequential
  "Histogram rendering includes le buckets, +Inf, _sum, and _count lines."
  (let ((h (rt-make-histogram "lat" '(1 5))))
    (rt-histogram-observe! h 3)
    (let ((text (prometheus-text-format (list h))))
      (expect (search "# TYPE lat histogram" text) :to-be-truthy)
      (expect (search "lat_bucket{le=\"+Inf\"} 1" text) :to-be-truthy)
      (expect (search "lat_count 1" text) :to-be-truthy))))

(it-sequential
  "A gauge renders a TYPE gauge comment and its value."
  (let ((g (rt-make-gauge "queue_depth")))
    (rt-gauge-set! g 7)
    (let ((text (prometheus-text-format (list g))))
      (expect (search "# TYPE queue_depth gauge" text) :to-be-truthy)
      (expect (search "queue_depth 7." text) :to-be-truthy))))

(it-sequential
  "Registered metrics appear when formatting the whole registry."
  (clrhash cl-cc/runtime::*rt-metrics-registry*)
  (let ((c (rt-make-counter "registered_total")))
    (rt-counter-increment! c 5)
    (rt-register-metric c)
    (let ((text
          (with-output-to-string (s)
            (rt-metrics-format-prometheus s))))
      (expect (search "registered_total 5" text) :to-be-truthy))))

;;; ── gc-stats passthrough ──────────────────────────────────────────
(it-sequential
  "gc-stats returns a plist exposing the stable public GC fields."
  (let ((stats (gc-stats)))
    (expect (listp stats) :to-be-truthy)
    (expect (member :minor-gcs stats) :to-be-truthy)
    (expect (member :major-gcs stats) :to-be-truthy)))
