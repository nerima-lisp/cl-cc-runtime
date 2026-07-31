;;;; heap-access.lisp — Heap construction (make-rt-heap) and the core
;;;; word read/write primitives. Relocation/compressed-pointer support is in
;;;; heap-forwarding.lisp, NUMA placement in heap-numa.lisp, and
;;;; occupancy/fragmentation stats in heap-stats.lisp.
(in-package :cl-cc/runtime)

;;; ------------------------------------------------------------
;;; make-rt-heap Factory
;;; ------------------------------------------------------------

(defun make-rt-heap (&key (young-size *gc-young-size-words* young-size-p)
                           (old-size   *gc-old-size-words* old-size-p))
  "Allocate and initialize a fresh managed heap.

   YOUNG-SIZE is the total young generation size in words; it is split
   evenly into two semi-spaces of YOUNG-SIZE/2 words each.
   OLD-SIZE is the old generation size in words.

   Layout of the flat word vector:
     [0 .. semi-size-1]                from-space
     [semi-size .. 2*semi-size-1]      to-space
     [2*semi-size .. 2*semi-size+old-1] old space"
  (unless (or young-size-p old-size-p)
    (rt-gc-auto-configure-heap)
    (setf young-size *gc-young-size-words*
          old-size *gc-old-size-words*))
  (let* (;; --- Layout arithmetic ---
         (semi-size           (floor young-size 2))
         (large-obj-size      old-size)
         (managed-words       (+ (* 2 semi-size) old-size large-obj-size))
         (heap-base           (if *rt-heap-randomize*
                                  (rt-heap-randomize-base managed-words)
                                  (rt-heap-randomize-base)))
         (young-from-base     heap-base)
         (young-to-base       (+ young-from-base semi-size))
         (old-base            (+ young-to-base semi-size))
         (large-obj-base      (+ old-base old-size))
         (total-size          (+ heap-base managed-words))
         ;; --- Storage allocation ---
         (words               (make-array total-size :initial-element 0))
         (num-cards           (ceiling old-size +gc-card-size-words+))
         (card-table          (make-array num-cards
                                         :element-type '(unsigned-byte 8)
                                         :initial-element 0))
         (card-summary        (make-array (ceiling num-cards +gc-card-summary-block-size+)
                                          :initial-element nil))
         (age-hist            (make-array 16 :initial-element 0))
         (free-bins           (make-array +rt-free-list-bin-count+ :initial-element nil))
         (slab-pools          (make-hash-table :test #'eql))
         ;; --- Ancillary hash tables ---
         (access-bits         (make-hash-table :test #'eql))
         (recent-promotions   (make-hash-table :test #'eql))
         (forwarding-table    (make-hash-table :test #'eql))
         (numa-node-map       (make-hash-table :test #'eql))
         (co-location-hints   (make-hash-table :test #'eql))
         ;; --- Growth / cap policy ---
         ;; FR-391: 0 means unlimited dynamic growth; positive *GC-MAX-HEAP-WORDS*
         ;; caps RT-HEAP-MAYBE-GROW.
         (max-heap-words      (if (plusp *gc-max-heap-words*) *gc-max-heap-words* 0))
         ;; --- Wall-clock timestamp ---
         (now                 (get-internal-real-time)))
    (when (and *compressed-pointers-enabled*
               (> managed-words +compressed-heap-region-words+))
      (error "cl-cc/runtime: compressed pointers require heap <= 4GB (~D words requested, max ~D)"
             managed-words +compressed-heap-region-words+))
    (when *compressed-pointers-enabled*
      (setf *heap-base-address* young-from-base))
    (%make-rt-heap
     :words                          words
     :young-from-base                young-from-base
     :young-to-base                  young-to-base
     :young-semi-size                semi-size
     :young-free                     young-from-base
     :old-base                       old-base
     :old-size                       old-size
     :old-free                       old-base
     :minor-gc-count                 0
     :major-gc-count                 0
     :words-collected                0
     :words-promoted                 0
     :card-table                     card-table
     :card-summary                   card-summary
     :num-cards                      num-cards
     :roots                          nil
     :satb-queue                     nil
     :barrier-buffer                 nil
     :free-list                      nil
     :free-bins                      free-bins
     :slab-pools                     slab-pools
     :lazy-sweep-cursor              old-base
     :lazy-sweep-limit               old-base
     :incremental-work-budget        64
     :pause-exceeded-count           0
     :access-bits                    access-bits
     :recent-promotions              recent-promotions
     :gc-state                       :normal
     :total-alloc-words              0
     :age-hist                       age-hist
     :large-obj-threshold            8192
     :large-obj-base                 large-obj-base
     :large-obj-size                 large-obj-size
     :large-obj-free                 large-obj-base
     :gc-pause-total                 0.0d0
     :gc-pause-max                   0.0d0
     :gc-wall-start-tick             now
     :allocation-rate-words-per-sec  0.0d0
     :allocation-rate-last-tick      now
     :allocation-rate-last-total     0
     :pressure-hooks                 nil
     :pressure-threshold-high        80.0d0
     :pressure-threshold-low         20.0d0
     :max-heap-words                 max-heap-words
     :initial-heap-words             total-size
     :initial-old-size               old-size
     :initial-large-obj-size         large-obj-size
     :shrink-threshold               0.25d0
     :shrink-counter                 0
     :compaction-trigger-fraction    0.5d0
     :forwarding-table               forwarding-table
     :numa-node-map                  numa-node-map
     :numa-gc-schedule               nil
     :interleaved-regions            nil
     :co-location-hints              co-location-hints
     :gc-inhibit                     nil
     :gc-pending                     nil)))

(defun rt-heap-ref (heap index)
  "Read word at absolute INDEX from HEAP.

FR-342 relocation barrier: during concurrent relocation, pointer-like values are
checked against RT-HEAP-FORWARDING-TABLE. A forwarded slot is self-healed in
place and the updated value is returned, amortizing stale-pointer repair."
  (%rt-sanitizer-check-heap-access heap index :read)
  (%rt-msan-check-read index)
  (when (and (rt-heap-access-bits heap)
             (integerp index)
             (or (and (>= index (rt-heap-young-from-base heap))
                      (< index (+ (rt-heap-young-from-base heap)
                                  (rt-heap-young-semi-size heap))))
                 (and (>= index (rt-heap-old-base heap))
                      (< index (+ (rt-heap-old-base heap)
                                  (rt-heap-old-size heap))))
                 (and (>= index (rt-heap-large-obj-base heap))
                      (< index (+ (rt-heap-large-obj-base heap)
                                  (rt-heap-large-obj-size heap))))))
    (setf (gethash index (rt-heap-access-bits heap))
          (rt-heap-minor-gc-count heap)))
  (let* ((value (svref (rt-heap-words heap) index))
         (table (rt-heap-forwarding-table heap))
         (old-addr (cond
                     ((and (integerp value) (val-pointer-p value))
                      (decode-pointer value))
                     ((integerp value) value)
                     (t nil)))
         (new-addr (and table old-addr (gethash old-addr table))))
    (if new-addr
        (let ((healed (if (and (integerp value) (val-pointer-p value))
                          (encode-pointer new-addr (pointer-tag value))
                          new-addr)))
          (setf (svref (rt-heap-words heap) index) healed)
          healed)
        value)))

(defun rt-heap-set (heap index value)
  "Write VALUE at absolute INDEX in HEAP."
  (%rt-sanitizer-check-heap-access heap index :write)
  (%rt-with-sanitizer-map-lock ()
    (setf (gethash index *rt-heap-init-map*) t))
  (setf (svref (rt-heap-words heap) index) value))

(defun rt-heap-object-header (heap addr)
  "Read the header word of the object at absolute word address ADDR."
  (rt-heap-ref heap addr))

(defun rt-heap-set-header (heap addr new-header)
  "Write NEW-HEADER as the header of the object at absolute word address ADDR."
  (rt-heap-set heap addr new-header))

(defun rt-heap-object-size (heap addr)
  "Return the size in words of the object at absolute word address ADDR."
  (rt-header-size (rt-heap-object-header heap addr)))
