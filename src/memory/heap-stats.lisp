;;;; heap-stats.lisp — Heap occupancy, fragmentation, and compaction-trigger
;;;; queries, split out of heap-access.lisp
(in-package :cl-cc/runtime)

(defun rt-heap-occupancy-pct (heap)
  "Return total young+old heap occupancy as a percentage.

The numerator is the active young from-space cursor plus the old-generation
allocation cursor.  The denominator is one young semi-space plus the old-space
capacity, matching the capacities reported by RT-GC-STATS."
  (let* ((young-used (- (rt-heap-young-free heap)
                        (rt-heap-young-from-base heap)))
         (old-used (- (rt-heap-old-free heap)
                      (rt-heap-old-base heap)))
         (used (+ young-used old-used))
         (total (+ (rt-heap-young-semi-size heap)
                   (rt-heap-old-size heap))))
    (if (plusp total)
        (* 100.0d0 (/ used total))
        0.0d0)))

(defun rt-heap-register-pressure-hook (heap hook)
  "Register HOOK to be called with (HEAP LEVEL OCCUPANCY-PCT) after GC pressure checks."
  (check-type hook function)
  (pushnew hook (rt-heap-pressure-hooks heap) :test #'eq)
  hook)

(defun rt-heap-fragmentation-pct (heap)
  "Return old-space fragmentation as free-list words divided by old-space size."
  (let ((free-words (loop for (size . nil) in (rt-heap-free-list-blocks heap) sum size))
        (old-size (rt-heap-old-size heap)))
    (if (plusp old-size)
        (/ (float free-words 1.0d0) old-size)
        0.0d0)))

(defun rt-heap-should-compact-p (heap)
  "Return true when fragmentation exceeds the configured compaction trigger."
  (> (rt-heap-fragmentation-pct heap)
     (rt-heap-compaction-trigger-fraction heap)))

(defun %rt-heap-live-used-words (heap)
  "Return the current used words in young, old, and large-object spaces."
  (+ (- (rt-heap-young-free heap) (rt-heap-young-from-base heap))
     (- (rt-heap-old-free heap) (rt-heap-old-base heap))
     (- (rt-heap-large-obj-free heap) (rt-heap-large-obj-base heap))))
