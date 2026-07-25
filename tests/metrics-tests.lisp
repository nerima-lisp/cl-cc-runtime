(in-package :cl-cc-runtime/test)
(in-suite cl-cc-unit-suite)

;;;; Tests for src/metrics.lisp — FR-792 Prometheus-compatible metrics.
;;;;
;;;; Covers counter/gauge/histogram data structures, the non-cumulative bucket
;;;; assignment used by rt-histogram-observe!, and both Prometheus text emitters.
;;;; Metric struct accessors are unexported (cl-cc/runtime:: below); the global
;;;; registry is cleared before the tests that iterate it.

;;; ── Counter ───────────────────────────────────────────────────────

(deftest metrics-counter-increments
  "Counter increment adds N (default 1) and returns the new value."
  (let ((c (rt-make-counter "reqs")))
    (assert-= 1 (rt-counter-increment! c))
    (assert-= 4 (rt-counter-increment! c 3))
    (assert-= 4 (cl-cc/runtime::rt-counter-value c))))

(cl-weave:it-property "metrics counter value equals sum of increments"
    ((deltas (cl-weave:gen-list (cl-weave:gen-integer :min 0 :max 1000)
                                :max-length 10)))
  (let ((c (rt-make-counter "p")))
    (dolist (d deltas) (rt-counter-increment! c d))
    (cl-weave:expect (cl-cc/runtime::rt-counter-value c)
                     :to-be (reduce #'+ deltas :initial-value 0))))

;;; ── Gauge ─────────────────────────────────────────────────────────

(deftest metrics-gauge-set-coerces-to-double
  "Gauge set stores a double-float value that can rise and fall."
  (let ((g (rt-make-gauge "temp")))
    (rt-gauge-set! g 5)
    (assert-= 5d0 (cl-cc/runtime::rt-gauge-value g))
    (rt-gauge-set! g 2)
    (assert-= 2d0 (cl-cc/runtime::rt-gauge-value g))))

;;; ── Histogram ─────────────────────────────────────────────────────

(deftest metrics-histogram-buckets-are-sorted
  "Buckets are stored in ascending order regardless of input order."
  (let ((h (rt-make-histogram "h" '(10 1 5))))
    (assert-equal '(1 5 10) (cl-cc/runtime::rt-histogram-buckets h))))

(deftest metrics-histogram-observe-assigns-first-fitting-bucket
  "Each observation lands in the first bucket whose bound it does not exceed."
  (let ((h (rt-make-histogram "h" '(1 5 10))))
    (rt-histogram-observe! h 0.5)   ; -> bucket 0 (<=1)
    (rt-histogram-observe! h 3)     ; -> bucket 1 (<=5)
    (rt-histogram-observe! h 5)     ; -> bucket 1 (<=5)
    (assert-equal '(1 2 0) (cl-cc/runtime::rt-histogram-counts h))))

(deftest metrics-histogram-overflow-goes-to-last-bucket
  "A value above every bound is counted in the final bucket."
  (let ((h (rt-make-histogram "h" '(1 5 10))))
    (rt-histogram-observe! h 100)
    (assert-equal '(0 0 1) (cl-cc/runtime::rt-histogram-counts h))))

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

(deftest metrics-prometheus-counter-without-labels
  "A bare counter renders a TYPE comment and a name/value line."
  (let ((text (prometheus-text-format
               (list (rt-make-counter "http_requests")))))
    (assert-true (search "# TYPE http_requests counter" text))
    (assert-true (search "http_requests 0" text))))

(deftest metrics-prometheus-counter-labels-lowercased
  "Label keys are normalized to lowercase in the rendered output."
  (let* ((c (rt-make-counter "reqs" :labels '(:METHOD "GET")))
         (text (prometheus-text-format (list c))))
    (assert-true (search "method=\"GET\"" text))))

(deftest metrics-prometheus-histogram-emits-buckets-sum-count
  "Histogram rendering includes le buckets, +Inf, _sum, and _count lines."
  (let ((h (rt-make-histogram "lat" '(1 5))))
    (rt-histogram-observe! h 3)
    (let ((text (prometheus-text-format (list h))))
      (assert-true (search "# TYPE lat histogram" text))
      (assert-true (search "lat_bucket{le=\"+Inf\"} 1" text))
      (assert-true (search "lat_count 1" text)))))

(deftest metrics-prometheus-gauge-renders-value
  "A gauge renders a TYPE gauge comment and its value."
  (let ((g (rt-make-gauge "queue_depth")))
    (rt-gauge-set! g 7)
    (let ((text (prometheus-text-format (list g))))
      (assert-true (search "# TYPE queue_depth gauge" text))
      (assert-true (search "queue_depth 7." text)))))

(deftest metrics-registry-format-includes-registered-metric
  "Registered metrics appear when formatting the whole registry."
  (clrhash cl-cc/runtime::*rt-metrics-registry*)
  (let ((c (rt-make-counter "registered_total")))
    (rt-counter-increment! c 5)
    (rt-register-metric c)
    (let ((text (with-output-to-string (s)
                  (rt-metrics-format-prometheus s))))
      (assert-true (search "registered_total 5" text)))))

;;; ── gc-stats passthrough ──────────────────────────────────────────

(deftest metrics-gc-stats-returns-public-plist
  "gc-stats returns a plist exposing the stable public GC fields."
  (let ((stats (gc-stats)))
    (assert-true (listp stats))
    (assert-true (member :minor-gcs stats))
    (assert-true (member :major-gcs stats))))
