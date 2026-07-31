;;;; gc-compact.lisp — Old-space compaction and its trigger heuristic, split
;;;; out of gc-major-sweep.lisp
(in-package :cl-cc/runtime)

(defun rt-gc-should-run-compaction-p (heap)
  "Return true when FR-621 old-generation mark-compact should run."
  (and *compacting-gc-enabled*
       (or (rt-heap-should-compact-p heap)
           (and (plusp *gc-compact-after-major-cycles*)
                (plusp (rt-heap-major-gc-count heap))
                (zerop (mod (rt-heap-major-gc-count heap)
                            *gc-compact-after-major-cycles*))))))

(defun rt-gc-compact-old-space (heap)
  "Sliding compaction of old space (FR-089/FR-213).

Algorithm:
  1. Walk old space, build forwarding table: live objects are assigned
     contiguous addresses starting from RT-HEAP-OLD-BASE.  Pinned objects
     stay in place (they are relocation barriers).
  2. Update all pointer slots (roots, young, old, large-object spaces) to
     use forwarded addresses.
  3. Copy each moved object to its new location (bottom-up traversal).
  4. Update old-free, rebuild free-list, reset card table.

Returns a plist describing the compaction result."
  (check-type heap rt-heap)
  (let* ((old-base (rt-heap-old-base heap))
         (old-free (rt-heap-old-free heap))
         (forwarding (make-hash-table :test #'eql))
         (compact-cursor old-base)
         (live-count 0)
         (moved-count 0)
         (dead-words 0))
    ;; Phase 1: Compute new addresses + build forwarding table
    (loop with addr = old-base
          while (< addr old-free) do
            (let ((h (rt-heap-object-header heap addr)))
              (cond
                ((header-forwarding-p h)
                 (incf addr 1))
                ((or (not (integerp h)) (zerop (rt-header-size h)))
                 (setf addr old-free))
                ((header-marked-p h)
                 (let* ((size (rt-header-size h))
                        (pinned (rt-object-pinned-p heap addr))
                        (new-addr (if pinned addr compact-cursor)))
                   (unless (= new-addr addr)
                     (setf (gethash addr forwarding) new-addr)
                     (incf moved-count))
                   (incf live-count)
                    (setf compact-cursor
                          (if pinned
                              ;; Pinned FFI objects are relocation barriers for
                              ;; the Lisp2 slide: subsequent objects must not be
                              ;; assigned into the pinned object's address range.
                              (max compact-cursor (+ addr size))
                              (+ new-addr size)))
                   (incf addr size)))
                (t
                 (let ((size (rt-header-size h)))
                   (incf dead-words size)
                   (incf addr size))))))
    (let ((new-old-free compact-cursor))
      ;; Phase 2: Update pointer slots throughout the heap using forwarding table
      (labels ((maybe-forward (value)
                 (if (and (integerp value) (val-pointer-p value))
                     (let* ((a (decode-pointer value))
                            (na (gethash a forwarding)))
                       (if na (encode-pointer na (pointer-tag value)) value))
                     value))
               (update-range (start end)
                 (loop with a = start
                       while (< a end) do
                         (let ((h (rt-heap-object-header heap a)))
                           (cond
                             ((header-forwarding-p h) (incf a 1))
                             ((and (integerp h) (> (rt-header-size h) 0))
                              (let ((size (rt-header-size h)))
                                (dolist (offset (rt-object-pointer-slots heap a))
                                  (let ((slot (+ a offset)))
                                    (rt-heap-set heap slot
                                                 (maybe-forward (rt-heap-ref heap slot)))))
                                (incf a size)))
                             (t (return)))))))
        ;; 2a. Roots
        (dolist (root-cell (rt-heap-roots heap))
          (setf (cdr root-cell) (maybe-forward (cdr root-cell))))
        ;; 2b. Binding stacks and globals
        (dolist (thread-state *gc-threads*)
          (dolist (binding (%rt-gc-thread-binding-stack thread-state))
            (%rt-gc-set-binding-value binding
             (maybe-forward (%rt-gc-binding-value binding)))))
        (when (boundp '*rt-global-var-registry*)
          (maphash (lambda (sym val)
                     (setf (gethash sym *rt-global-var-registry*)
                           (maybe-forward val)))
                   *rt-global-var-registry*))
        ;; 2c-2e. Update pointer slots in each space
        (update-range (rt-heap-young-from-base heap) (rt-heap-young-free heap))
        (update-range old-base old-free)
        (update-range (rt-heap-large-obj-base heap) (rt-heap-large-obj-free heap))
        ;; 2f-2g. Update SATB and barrier queues
        (setf (rt-heap-satb-queue heap)
              (mapcar (lambda (x) (maybe-forward x)) (rt-heap-satb-queue heap)))
        (setf (rt-heap-barrier-buffer heap)
              (mapcar (lambda (x) (maybe-forward x)) (rt-heap-barrier-buffer heap))))
      ;; Phase 3: Move objects (bottom-up, safe because destinations ≤ sources)
      (loop with addr = old-base
            while (< addr old-free) do
              (let ((h (rt-heap-object-header heap addr)))
                (cond
                  ((header-forwarding-p h)
                   (incf addr 1))
                  ((or (not (integerp h)) (zerop (rt-header-size h)))
                   (setf addr old-free))
                  ((header-marked-p h)
                   (let ((size (rt-header-size h))
                         (new-addr (gethash addr forwarding addr)))
                     (unless (= new-addr addr)
                       ;; Copy words from old location to new location
                       (loop for i from 0 below size do
                         (rt-heap-set heap (+ new-addr i)
                                      (rt-heap-ref heap (+ addr i))))
                       ;; Install forwarding pointer so future scans react correctly
                       (rt-heap-set-header heap addr
                                           (header-make-forwarding-ptr new-addr))
                       ;; Clear mark bit at new location
                       (let ((new-h (rt-heap-object-header heap new-addr)))
                         (rt-heap-set-header heap new-addr
                                             (header-clear-mark new-h))))
                     ;; Clear mark bit at original location (may not match addr if moved)
                     (unless (= new-addr addr)
                       (let ((hdr (rt-heap-object-header heap addr)))
                         (when (integerp hdr)
                           (rt-heap-set-header heap addr (header-clear-mark hdr)))))
                     (incf addr size)))
                  (t
                   ;; Dead — skip
                   (incf addr (rt-header-size h))))))
      ;; Phase 4: Update metadata
      (setf (rt-heap-old-free heap) new-old-free)
      ;; Clear card table (all old→young relationships must be re-recorded)
      (rt-card-clear-all heap)
      ;; Rebuild free-list for whatever dead space remains after compaction
      (%rt-free-list-rebuild-bins heap nil)
      ;; Record stats
      (when (plusp moved-count)
        (incf (rt-heap-words-collected heap) dead-words))
      ;; Return result plist
      (list :status :compact-done
            :algorithm :sliding-compaction
            :pinned-objects-preserved t
            :live-count live-count
            :moved-count moved-count
            :dead-words dead-words
            :old-free-before old-free
            :old-free-after new-old-free
            :fragmentation-before (rt-heap-fragmentation-pct heap)
            :fragmentation-after (if (plusp (- new-old-free old-base))
                                     (/ (float dead-words 1.0d0)
                                        (- new-old-free old-base))
                                     0.0d0)))))
