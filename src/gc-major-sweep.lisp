;;;; gc-major-sweep.lisp — Old-space mark-sweep pass and free-list coalescing.
;;;; Compaction in gc-compact.lisp, the concurrent sweep worker in
;;;; gc-concurrent-sweep.lisp, and the major-GC orchestrator in
;;;; gc-major-collect.lisp.
(in-package :cl-cc/runtime)

(defun %gc-sweep-old-space (heap)
  "Sweep the old generation: reclaim all unmarked (dead) objects by adding them
   to the free-list, and clear the mark bit on all live (marked) objects."
  (let ((addr     (rt-heap-old-base heap))
        (old-free (rt-heap-old-free heap))
        (freed    0))
    (%rt-free-list-rebuild-bins heap nil)
    (loop while (< addr old-free) do
      (let ((h (rt-heap-object-header heap addr)))
        (cond
          ((header-forwarding-p h)
           ;; Forwarding pointer should not appear in old space — skip 1 word
           (incf addr 1))
          ((not (integerp h))
           ;; Non-integer, non-cons header — stop
           (return))
          ((zerop (rt-header-size h))
           ;; Zero size header (uninitialized region) — stop
           (return))
          ((header-marked-p h)
           ;; Live object: clear mark bit and advance
           (rt-heap-set-header heap addr (header-clear-mark h))
           (incf addr (rt-header-size h)))
          (t
             ;; Dead object: reclaim to segregated free-list
             (let ((size (rt-header-size h)))
               (dolist (hook *rt-gc-death-hooks*)
                 (funcall hook heap addr size))
               (rt-free-list-insert heap size addr)
              (incf freed size)
              (incf addr size))))))
    ;; Coalesce adjacent free blocks (FR-398)
    (%rt-free-list-rebuild-bins
     heap (%gc-coalesce-free-list (rt-heap-free-list-blocks heap)))
    (when *gc-profile-guided-placement*
      (%rt-free-list-rebuild-bins
       heap (%rt-gc-profile-guide-free-list heap (rt-heap-free-list-blocks heap))))
    (setf (rt-heap-lazy-sweep-cursor heap) old-free
          (rt-heap-lazy-sweep-limit heap) old-free)
    (incf (rt-heap-words-collected heap) freed)))

;;; FR-340: Concurrent Sweeping — sweeps old space on-demand during allocation; lazy sweep with
;;; page-level granularity
(defun rt-gc-lazy-sweep-step (heap region-start &key (page-words +gc-card-size-words+))
  "Sweep one old-space page starting at REGION-START and enqueue dead blocks."
  (check-type heap rt-heap)
  (let* ((old-free (rt-heap-old-free heap))
         (limit (min old-free (+ region-start page-words)))
         (addr region-start)
         (freed 0))
    (loop while (< addr limit) do
      (let ((h (rt-heap-object-header heap addr)))
        (cond
          ((header-forwarding-p h) (incf addr 1))
          ((or (not (integerp h)) (zerop (rt-header-size h)))
           (setf addr limit))
          ((header-marked-p h)
           (rt-heap-set-header heap addr (header-clear-mark h))
           (incf addr (rt-header-size h)))
          (t
           (let ((size (rt-header-size h)))
             (dolist (hook *rt-gc-death-hooks*)
               (funcall hook heap addr size))
             (rt-free-list-insert heap size addr)
             (incf freed size)
             (incf addr size))))))
    (setf (rt-heap-lazy-sweep-cursor heap)
          (max (rt-heap-lazy-sweep-cursor heap) addr))
    (when (>= (rt-heap-lazy-sweep-cursor heap) (rt-heap-lazy-sweep-limit heap))
      (%rt-free-list-rebuild-bins
       heap (%gc-coalesce-free-list (rt-heap-free-list-blocks heap))))
    (incf (rt-heap-words-collected heap) freed)
    freed))

(defun %gc-coalesce-free-list (free-list)
  "Coalesce adjacent free blocks in the free-list.
   Sorts by address, then merges blocks where (addr1 + size1) = addr2."
  (if (null free-list)
      nil
      (let* ((sorted (sort (copy-list free-list) #'< :key #'cdr))
             (result nil)
             (current (car sorted)))
        (dolist (block (cdr sorted))
          (let ((cur-size (car current))
                (cur-addr (cdr current))
                (next-size (car block))
                (next-addr (cdr block)))
            (if (= (+ cur-addr cur-size) next-addr)
                ;; Adjacent blocks — merge
                (setf current (cons (+ cur-size next-size) cur-addr))
                ;; Non-adjacent — push current and start new
                (progn
                  (push current result)
                  (setf current block)))))
        (push current result)
        (nreverse result))))

(defun %rt-gc-block-hot-neighbor-score (heap block)
  "Return a small priority score for free-list BLOCK based on adjacent objects."
  (destructuring-bind (size . addr) block
    (let* ((before (max (rt-heap-old-base heap) (1- addr)))
           (after (+ addr size))
           (score 0))
      (declare (ignore before))
      ;; We cannot cheaply find the previous object start in an unindexed
      ;; mark-sweep heap, so this FR-468 hook scores the next object.  The hook is
      ;; deliberately isolated for the future compactor/object index to refine.
      (when (and (< after (rt-heap-old-free heap))
                 (integerp (rt-heap-object-header heap after)))
        (case (rt-gc-classify-hotness heap after)
          (:hot (incf score 2))
          (:warm (incf score 1))))
      score)))

(defun %rt-gc-profile-guide-free-list (heap free-list)
  "Order FREE-LIST so allocations prefer holes adjacent to hot/warm objects."
  (stable-sort (copy-list free-list) #'>
               :key (lambda (block)
                      (%rt-gc-block-hot-neighbor-score heap block))))
