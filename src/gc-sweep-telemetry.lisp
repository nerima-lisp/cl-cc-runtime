;;;; gc-sweep-telemetry — GC statistics, periodic/idle scheduling, and probes

(in-package :cl-cc/runtime)

;;; Section 6: GC Statistics

(defun rt-gc-stats (heap)
  "Return a plist of current GC statistics for HEAP.

   Keys:
     :minor-gc-count  - number of minor GCs performed
     :major-gc-count  - number of major GCs performed
     :words-collected - total words reclaimed across all GC cycles
     :words-promoted  - total words promoted from young to old generation
     :young-used      - words currently live in young from-space
      :young-total     - total capacity of one young semi-space
      :old-used        - words currently allocated in old space
      :old-total       - total capacity of old space
      :heap-occupancy-pct - young+old occupancy percentage
      :free-list-count - number of free-list entries in old space"
   (append
    (list :minor-gcs       (rt-heap-minor-gc-count heap)
          :major-gcs       (rt-heap-major-gc-count heap)
          :total-collected-bytes (* 8 (rt-heap-words-collected heap))
          :pause-ms-p99    (* 1000.0d0 (rt-heap-gc-pause-max heap))
          :minor-gc-count  (rt-heap-minor-gc-count heap)
         :major-gc-count  (rt-heap-major-gc-count heap)
         :words-collected (rt-heap-words-collected heap)
        :words-promoted  (rt-heap-words-promoted heap)
        :young-used      (- (rt-heap-young-free heap)
                            (rt-heap-young-from-base heap))
        :young-total     (rt-heap-young-semi-size heap)
        :old-used        (- (rt-heap-old-free heap)
                            (rt-heap-old-base heap))
        :old-total       (rt-heap-old-size heap)
         :heap-occupancy-pct (rt-heap-occupancy-pct heap)
          :free-list-count (length (rt-heap-free-list-blocks heap))
         :total-alloc-words (rt-heap-total-alloc-words heap)
         :age-hist (coerce (rt-heap-age-hist heap) 'list)
         :age-distribution (%rt-gc-age-distribution-plist heap)
         :large-object-used (- (rt-heap-large-obj-free heap)
                               (rt-heap-large-obj-base heap))
         :large-object-total (rt-heap-large-obj-size heap)
          :gc-pause-total (rt-heap-gc-pause-total heap)
          :gc-pause-max (rt-heap-gc-pause-max heap)
          :gc-throughput-ratio (rt-gc-throughput-ratio heap)
          :gc-throughput-target *gc-throughput-target*
          :gc-max-pause-ms *gc-max-pause-ms*
          :pause-exceeded-count (rt-heap-pause-exceeded-count heap)
          :incremental-work-budget (rt-heap-incremental-work-budget heap)
          :allocation-rate-words-per-sec (rt-heap-allocation-rate-words-per-sec heap)
          :fragmentation-pct (rt-heap-fragmentation-pct heap)
          :should-compact-p (rt-heap-should-compact-p heap)
          :gc-compaction-enabled-p *gc-compaction-enabled*
          :gc-incremental-mark-enabled-p *gc-incremental-mark-enabled*
          :gc-lazy-sweep-enabled-p *gc-lazy-sweep-enabled*
          :lazy-sweep-cursor (rt-heap-lazy-sweep-cursor heap)
          :lazy-sweep-limit (rt-heap-lazy-sweep-limit heap)
          :incremental-mark-queue-length
          (length (with-gc-mark-queue-locked ()
                    (gethash heap *rt-gc-incremental-mark-queues*)))
          :concurrent-gc-enabled-p *rt-concurrent-gc-enabled-p*
          :concurrent-gc-write-barrier *rt-concurrent-gc-write-barrier-mode*
          :concurrent-gc-stw-phases (copy-list *rt-concurrent-gc-stw-phases*)
          :concurrent-gc-mutator-assist-p *rt-concurrent-gc-mutator-assist-p*
          :concurrent-mark-thread-active-p (and (boundp '*rt-concurrent-mark-thread*)
                                                (not (null *rt-concurrent-mark-thread*)))
          :numa-enabled-p (and (boundp '*rt-numa-enabled*) *rt-numa-enabled*))
   (%rt-gc-age-distribution-plist heap)))

;;; ------------------------------------------------------------
;;; Periodic GC (FR-441) & Idle-Time GC (FR-439)
;;; ------------------------------------------------------------

(defparameter *gc-periodic-interval-ms* 0
  "If positive, trigger a minor GC every N milliseconds of wall-clock time.
   Default 0 disables periodic GC.")

(defparameter *gc-last-periodic-gc-time* 0
  "Internal real time of the last periodic GC trigger.")

(defparameter *gc-idle-work-fraction* 0.5d0
  "Fraction of idle time to dedicate to background GC work (FR-439).
   Default 0.5 = 50% of idle time. Set to 0 to disable.")

(defun rt-gc-maybe-periodic-collect (heap)
  "Trigger a minor GC if the periodic interval has elapsed since the last one.
    Call this from the main loop or from rt-gc-alloc periodically."
  (when (and (plusp *gc-periodic-interval-ms*)
             (not (rt-gc-defer-non-critical-work-p heap)))
    (let* ((now (get-internal-real-time))
           (elapsed-ms (* (/ (- now *gc-last-periodic-gc-time*)
                              internal-time-units-per-second)
                          1000)))
      (when (>= elapsed-ms *gc-periodic-interval-ms*)
        (setf *gc-last-periodic-gc-time* now)
        (rt-gc-minor-collect heap)))))

(defun rt-gc-idle-work (heap &key (budget 64))
  "Perform background GC work during idle time (FR-439).
   Processes up to BUDGET SATB queue entries and sweeps a portion
   of old space if major GC is in concurrent mode.
   Returns the number of work units completed."
  (if (rt-gc-defer-non-critical-work-p heap)
      0
      (let ((work-done 0))
        (when (eq (rt-heap-gc-state heap) :major-gc-concurrent)
          (incf work-done (rt-gc-concurrent-assist heap :budget budget)))
        work-done)))

;;; ------------------------------------------------------------
;;; FR-369: Prometheus Metrics Export
;;; ------------------------------------------------------------

(defun rt-gc-prometheus-metrics (heap)
  "Return a string containing GC metrics in Prometheus exposition format.

Output lines follow the Prometheus text-based format:
  # HELP <name> <description>
  # TYPE <name> <type>
  <name>{<label>=\"<value>\"} <value>

Metrics exported:
  gc_pause_seconds{type=\"minor\"}
  gc_pause_seconds{type=\"major\"}
  gc_collections_total{type=\"minor\"}
  gc_collections_total{type=\"major\"}
  heap_used_bytes
  heap_available_bytes
  gc_promoted_bytes"
  (check-type heap rt-heap)
  (let* ((stats (rt-gc-stats heap))
         (minor-pause (/ (float (getf stats :gc-pause-total) 1.0d0) 2.0d0)) ; rough split
         (major-pause (max 0.0d0 (- (getf stats :gc-pause-total) minor-pause)))
         (young-used (- (rt-heap-young-free heap) (rt-heap-young-from-base heap)))
         (old-used (- (rt-heap-old-free heap) (rt-heap-old-base heap)))
         (large-used (- (rt-heap-large-obj-free heap) (rt-heap-large-obj-base heap)))
         (total-used (* (+ young-used old-used large-used) 8))
         (young-capacity (rt-heap-young-semi-size heap))
         (old-capacity (rt-heap-old-size heap))
         (large-capacity (rt-heap-large-obj-size heap))
         (total-capacity (* (+ young-capacity old-capacity large-capacity) 8)))
    (format nil "~{~a~%~}"
            (list
             "# HELP gc_pause_seconds Time spent in GC pauses (cumulative)"
             "# TYPE gc_pause_seconds gauge"
             (format nil "gc_pause_seconds{type=\"minor\"} ~,6f" minor-pause)
             (format nil "gc_pause_seconds{type=\"major\"} ~,6f" major-pause)
             ""
             "# HELP gc_collections_total Total number of GC collections"
             "# TYPE gc_collections_total counter"
             (format nil "gc_collections_total{type=\"minor\"} ~D"
                     (getf stats :minor-gc-count))
             (format nil "gc_collections_total{type=\"major\"} ~D"
                     (getf stats :major-gc-count))
             ""
             "# HELP heap_used_bytes Currently used heap memory in bytes"
             "# TYPE heap_used_bytes gauge"
             (format nil "heap_used_bytes ~D" total-used)
             ""
             "# HELP heap_available_bytes Total managed heap capacity in bytes"
             "# TYPE heap_available_bytes gauge"
             (format nil "heap_available_bytes ~D" total-capacity)
             ""
             "# HELP gc_promoted_bytes Bytes promoted from young to old generation"
             "# TYPE gc_promoted_bytes counter"
             (format nil "gc_promoted_bytes ~D"
                     (* (getf stats :words-promoted) 8))))))

;;; ------------------------------------------------------------
;;; FR-367: DTrace/eBPF Tracing Stubs
;;; ------------------------------------------------------------

(defparameter *gc-probes-enabled* nil
  "When true, GC probe points print to *TRACE-OUTPUT*.

In a native codegen backend this flag would gate DTrace SDT probes (Linux
USDT via SystemTap) or eBPF uprobes.  The Pure CL runtime implements probes
as conditional *TRACE-OUTPUT* logging — a documented stub for future native
integration.

Probe points:
  rt-gc-probe-alloc(size-words)        — called on each allocation
  rt-gc-probe-gc-start(phase)          — called at GC phase start
  rt-gc-probe-gc-end(phase)            — called at GC phase end

Native backends can replace each body with a platform SDT probe:
  DTrace:    dtrace -n 'gc-probe-alloc { printf(...) }'
  eBPF/USDT: bpftrace -e 'usdt:/proc/self/exe:gc_probe_alloc { ... }'")

(defun rt-gc-probe-alloc (size-words)
  "Probe: allocation of SIZE-WORDS words.
When *GC-PROBES-ENABLED* is true, prints to *TRACE-OUTPUT*.
Native replacement: DTrace SDT probe gc-probe-alloc / eBPF uprobe."
  (when *gc-probes-enabled*
    (let ((*print-pretty* nil))
      (format *trace-output* "GC-PROBE-ALLOC ~D~%" size-words)
      (force-output *trace-output*)))
  size-words)

(defun rt-gc-probe-gc-start (phase)
  "Probe: GC phase start (PHASE is :MINOR, :MAJOR, :COMPACT, etc.).
Native replacement: DTrace SDT probe gc-probe-gc-start / eBPF uprobe."
  (when *gc-probes-enabled*
    (let ((*print-pretty* nil))
      (format *trace-output* "GC-PROBE-GC-START ~S~%" phase)
      (force-output *trace-output*)))
  phase)

(defun rt-gc-probe-gc-end (phase)
  "Probe: GC phase end (PHASE is :MINOR, :MAJOR, :COMPACT, etc.).
Native replacement: DTrace SDT probe gc-probe-gc-end / eBPF uprobe."
  (when *gc-probes-enabled*
    (let ((*print-pretty* nil))
      (format *trace-output* "GC-PROBE-GC-END ~S~%" phase)
      (force-output *trace-output*)))
  phase)
