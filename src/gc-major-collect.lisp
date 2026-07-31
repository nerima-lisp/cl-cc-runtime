;;;; gc-major-collect.lisp — Top-level major-GC orchestrator driving mark,
;;;; sweep, and compaction, split out of gc-major-sweep.lisp
(in-package :cl-cc/runtime)

(defun rt-gc-major-collect (heap)
  "Perform a major GC of the old generation using tri-color mark-and-sweep.

   Algorithm:
   1. Set gc-state to :major-gc.
   2. Initial mark: grey all old-space objects directly reachable from roots
      and from young-space roots (scan young objects reachable from roots).
   3. Drain the SATB queue into the grey set (SATB invariant).
   4. Marking loop: repeatedly pop a grey object, mark it black, and grey all
      unvisited old-space children.
   5. Sweep: scan old space linearly, reclaiming unmarked objects to free-list
      and clearing mark bits on survivors.
   6. Reset gc-state to :normal and increment major-gc-count."
  (let ((pause-start (get-internal-real-time)))
  (setf (rt-heap-gc-state heap)
        (if *rt-concurrent-gc-enabled-p*
            :major-gc-concurrent
            :major-gc))
  (unwind-protect
      (let ((queue-cell (cons nil nil)))
        ;; Phase 1: initial mark (STW root snapshot).
        (%rt-gc-seed-major-roots heap queue-cell)
        ;; Phase 2: mark. In concurrent mode a host worker drains the grey queue
        ;; while mutators preserve the initial snapshot through SATB queues.
        (if *rt-concurrent-gc-enabled-p*
            (%rt-gc-run-concurrent-mark heap queue-cell)
            (if *gc-incremental-mark-enabled*
                (%rt-gc-drain-incremental-mark heap queue-cell)
                (%rt-gc-drain-major-mark-work heap queue-cell)))
        ;; Phase 3: final remark (STW SATB drain) and drain any newly grey work.
        (%rt-gc-drain-satb-to-grey heap queue-cell)
        (%rt-gc-drain-major-mark-work heap queue-cell)
        (when (fboundp '%rt-gc-sweep-hash-consing)
          (%rt-gc-sweep-hash-consing))
        ;; Weak refs / weak hash tables / finalizers are processed after the
        ;; strong graph is completely marked and before old-space sweep consumes
        ;; mark bits.  They never seed roots; ephemeron values are the only
        ;; conditional marking path and are drained before weak clearing.
        (let ((marked-set (and (fboundp '%rt-gc-build-marked-set)
                               (%rt-gc-build-marked-set heap))))
          (when marked-set
            (when (fboundp 'rt-gc-process-references)
              (rt-gc-process-references heap marked-set))
            (when (fboundp '%rt-gc-process-finalizers)
              (%rt-gc-process-finalizers heap marked-set))
            (when (fboundp '%rt-gc-process-phantom-references)
              (%rt-gc-process-phantom-references heap marked-set))))
        ;; FR-339: verify no black old-space object still points to a white
        ;; old-space object before marks are consumed by sweeping.
        (multiple-value-bind (ok violating-addr)
            (rt-gc-verify-tri-color-invariant heap)
          (unless ok
            (error "FR-339: tri-color invariant violated at old object ~D"
                   violating-addr)))
        ;; Phase 4: sweep old space.  Concurrent mode uses the same sweep worker
        ;; entry point as the background/lazy path; the portable Pure CL runtime
        ;; joins before returning so the public heap invariants remain unchanged.
        (if *rt-concurrent-gc-enabled-p*
            (rt-gc-concurrent-sweep heap)
            (if *gc-lazy-sweep-enabled*
                (progn
                  (%rt-free-list-rebuild-bins heap nil)
                  (setf (rt-heap-lazy-sweep-cursor heap) (rt-heap-old-base heap)
                        (rt-heap-lazy-sweep-limit heap) (rt-heap-old-free heap))
                  (rt-gc-lazy-sweep-step heap (rt-heap-lazy-sweep-cursor heap)))
                (if (plusp *gc-worker-count*)
                    (rt-gc-parallel-sweep heap *gc-worker-count*)
                    (%gc-sweep-old-space heap))))
        ;; FR-438: integrated class/code unload pass-through after sweeping.
        (rt-gc-run-unload-pass heap)
        (when (fboundp '%rt-gc-clean-adjustable-array-registry)
          (%rt-gc-clean-adjustable-array-registry heap)))
    ;; Always reset gc-state and increment count, even on error
    (with-gc-mark-queue-locked ()
      (remhash heap *rt-gc-incremental-mark-queues*))
    (setf (rt-heap-gc-state heap) :normal)
    (incf (rt-heap-major-gc-count heap)))
  (%rt-gc-check-pressure heap)
  (%rt-gc-note-pause heap pause-start)
  ;; FR-391: Heap Growth Policy / FR-392: Heap Shrink Policy — resize only
  ;; after a full old-generation collection has had a chance to reclaim garbage.
  ;; Growth wins over shrink if occupancy remains critically high after sweeping.
  (when (rt-gc-should-run-compaction-p heap)
    (rt-gc-compact-old-space heap))
  (unless (rt-heap-maybe-grow heap)
    (rt-heap-maybe-shrink heap))
  (when *gc-verify-after-collect*
    (rt-gc-verify-heap heap))
  heap))
