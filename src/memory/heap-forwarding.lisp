;;;; heap-forwarding.lisp — Concurrent-relocation forwarding table and
;;;; compressed object-reference codec, split out of heap-access.lisp
(in-package :cl-cc/runtime)

;;; ------------------------------------------------------------
;;; Heap Word Access
;;; ------------------------------------------------------------

(defun rt-gc-forward-object (heap old-addr new-addr)
  "Record an OLD-ADDR -> NEW-ADDR forwarding entry for concurrent relocation.

This is the public FR-342 forwarding table hook used by future compactors.  The
Pure CL implementation does not move payload words concurrently yet; it records
the relocation mapping and relies on RT-HEAP-REF's relocation barrier to heal
stale slots lazily as mutators read them."
  (check-type heap rt-heap)
  (check-type old-addr integer)
  (check-type new-addr integer)
  (setf (gethash old-addr (rt-heap-forwarding-table heap)) new-addr)
  new-addr)

(defun rt-gc-clear-forwarding-table (heap)
  "Clear all transient concurrent-relocation forwarding entries for HEAP."
  (check-type heap rt-heap)
  (clrhash (rt-heap-forwarding-table heap))
  heap)

;;; ------------------------------------------------------------
;;; FR-347: Compressed Object References (portable offset codec)
;;; ------------------------------------------------------------

(defun rt-compress-object-ref (heap addr)
  "Return ADDR as a 32-bit heap-relative offset for FR-347.

The Pure CL heap stores ordinary word addresses, but this helper exposes the
same contract a native backend would use for compressed object references:
OFFSET = ADDR - HEAP-BASE.  The offset is validated to fit in 32 bits so callers
can test density-sensitive paths without native pointer compression."
  (check-type heap rt-heap)
  (check-type addr integer)
  (let* ((base (rt-heap-young-from-base heap))
          (offset (- addr base)))
    (unless (<= 0 offset #xffffffff)
      (error "cl-cc/runtime: address ~D cannot be compressed relative to heap base ~D"
             addr base))
    offset))

(defun rt-decompress-object-ref (heap offset)
  "Expand a 32-bit heap-relative OFFSET back into an absolute heap word address."
  (check-type heap rt-heap)
  (check-type offset (integer 0 #xffffffff))
  (+ (rt-heap-young-from-base heap) offset))

(defun %rt-ensure-compressed-pointer-range (addr size-words)
  "Signal if [ADDR, ADDR+SIZE-WORDS) cannot be represented as a compressed pointer."
  (when *compressed-pointers-enabled*
    (let ((end-offset (- (+ addr size-words) *heap-base-address*)))
      (unless (<= 0 end-offset +compressed-heap-region-words+)
        (error "cl-cc/runtime: allocation [~D, ~D) escapes compressed 4GB heap region based at ~D"
               addr (+ addr size-words) *heap-base-address*)))))
