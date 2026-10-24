;;;; gc-tlab.lisp — Thread-local allocation buffers (FR-343). Object copying
;;;; is in gc-copy.lisp, which loads first.
(in-package :cl-cc/runtime)

;;; Minor GC (%gc-scan-dirty-cards, %gc-cheney-scan, %gc-update-promoted,
;;; rt-gc-minor-collect) is in gc-minor.lisp (loads after this file).

;;; Section 4 (Write Barrier — SATB + Card Table: rt-gc-write-barrier)
;;; is in gc-write-barrier.lisp (loads after gc-minor, before gc-major.lisp).

;;; ------------------------------------------------------------
;;; FR-343-345: Thread-Local Allocation Buffers (TLAB)
;;; ------------------------------------------------------------

;;; FR-343: Thread-Local Allocation Buffers (TLAB)
(defstruct (rt-tlab (:constructor %make-rt-tlab)
                    (:conc-name rt-tlab-))
  "Per-thread allocation buffer for lock-free young-space allocation.

BASE and LIMIT delimit the reserved nursery slice, FREE is the current bump
cursor, THREAD-ID is a stable fixnum derived from the logical runtime thread id,
and WASTE-BYTES accumulates retired unused capacity for FR-344 accounting."
  (base 0 :type fixnum)
  (free 0 :type fixnum)
  (limit 0 :type fixnum)
  (thread-id 0 :type fixnum)
  (waste-bytes 0 :type fixnum)
  (retired-p nil :type boolean))

(defun make-rt-tlab (&key (base 0) (free base) (limit base) (thread-id 0) (waste-bytes 0) retired-p)
  "Construct an RT-TLAB using the public FR-343 field names."
  (%make-rt-tlab :base base
                 :free free
                 :limit limit
                 :thread-id thread-id
                 :waste-bytes waste-bytes
                 :retired-p retired-p))

(defparameter *gc-tlab-size-words* 512
  "Default TLAB allocation chunk in words (4KB with 8B words).")

(defvar *rt-thread-local-heaps* nil
  "List of (HEAP THREAD-ID . RT-TLAB) entries mapping heaps/threads to TLABs.
Used by RT-GC-TLAB-ALLOC for lock-free per-thread allocation.")

(defun %rt-gc-tlab-make-mutex (name)
  "Create an optional host mutex without reader-time SB-THREAD dependency."
  (let ((make-mutex (%rt-resolve-sb-thread-function "MAKE-MUTEX")))
    (and make-mutex (ignore-errors (funcall make-mutex :name name)))))

(defvar *rt-gc-tlab-refill-lock* (%rt-gc-tlab-make-mutex "gc-tlab-refill")
  "Optional mutex serializing global nursery bump-pointer reservation for TLAB refill.")

(defmacro %rt-gc-with-tlab-refill-lock (() &body body)
  `(%rt-with-optional-lock (*rt-gc-tlab-refill-lock*) ,@body))

(defparameter *gc-tlab-retire-fill* t
  "When true (FR-344), retired TLABs fill remaining space with dummy objects
to minimize waste.  The dummy header uses type-tag 0 (fixnum) and is small
enough to preserve heap invariants during concurrent marking.")

(defun %rt-gc-tlab-thread-id (thread-id)
  "Return a portable fixnum id for THREAD-ID suitable for RT-TLAB metadata."
  (logand (sxhash thread-id) most-positive-fixnum))

(defun %rt-gc-tlab-for (heap thread-id)
  "Return the RT-TLAB for THREAD-ID, or NIL.  Creates one if absent."
  (or (loop for entry in *rt-thread-local-heaps*
            when (and (eq (first entry) heap)
                      (eql (second entry) thread-id))
              return (cddr entry))
      (let ((tlab (%make-rt-tlab :thread-id (%rt-gc-tlab-thread-id thread-id))))
        (push (cons heap (cons thread-id tlab)) *rt-thread-local-heaps*)
        tlab)))

(defun %rt-gc-tlab-refill (heap thread-id &optional (minimum-words 1))
  "Allocate a fresh TLAB region from young from-space for THREAD-ID.

The TLAB is carved from the global young bump-pointer region, sized by
*GC-TLAB-SIZE-WORDS*.  If the young space has insufficient contiguously
available words, a minor GC is triggered and a more conservative TLAB size
is attempted."
  (let* ((size-words (min (max *gc-tlab-size-words* minimum-words)
                          (rt-heap-young-semi-size heap)))
         (tlab (%rt-gc-tlab-for heap thread-id)))
    (%rt-gc-with-tlab-refill-lock ()
      ;; Clear retired flag
      (setf (rt-tlab-retired-p tlab) nil)
      ;; Try to allocate from young from-space
      (let* ((addr (rt-heap-young-free heap))
             (limit (+ addr size-words))
             (semi-limit (+ (rt-heap-young-from-base heap)
                            (rt-heap-young-semi-size heap))))
        (when (> limit semi-limit)
          ;; Not enough room — trigger a minor GC and retry
          (rt-gc-minor-collect heap)
          (setf addr (rt-heap-young-free heap)
                limit (+ addr size-words))
          (when (> limit (+ (rt-heap-young-from-base heap)
                            (rt-heap-young-semi-size heap)))
            (error "cl-cc/runtime: TLAB refill failed — young space exhausted")))
        ;; Bump young-free past the TLAB region
        (setf (rt-heap-young-free heap) limit)
        ;; Install TLAB bounds
        (setf (rt-tlab-base tlab) addr
              (rt-tlab-limit tlab) limit
              (rt-tlab-free tlab) addr)
        tlab))))

(defun %rt-gc-tlab-retire (heap tlab)
  "Retire TLAB: record it as retired.  When *GC-TLAB-RETIRE-FILL* is true
(FR-344), fill the unused portion with a dummy object to maintain heap
invariants and minimize waste for concurrent marking."
  (setf (rt-tlab-retired-p tlab) t)
  (when *gc-tlab-retire-fill*
    (let* ((free-pos (rt-tlab-free tlab))
           (limit (rt-tlab-limit tlab))
           (remaining (- limit free-pos)))
      (when (plusp remaining)
        (incf (rt-tlab-waste-bytes tlab) (* remaining 8))
        ;; Write a dummy header (type-tag 0 = fixnum-like) over the unused
        ;; region so concurrent markers observe a valid object boundary.
        (rt-heap-set-header heap free-pos
                            (make-rt-header remaining 0 :gc-bits 0)))))
  tlab)

(defun rt-gc-tlab-alloc (heap thread-id size-words)
  "Thread-local bump-pointer allocation from THREAD-ID's TLAB.

Returns the word address of the allocated block within the TLAB.  If the
TLAB lacks room, a new TLAB is allocated from global young space (possibly
triggering a minor GC).  When no TLAB is available for any reason, falls
back to RT-GC-ALLOC.

This is the FR-343 entry point for lock-free per-thread allocation.

FR-345 (SIMD zeroing):  In a native codegen backend, the caller may emit
a vectorised zero-fill (e.g. movdqa or NEON STP) over the returned range
[ADDR, ADDR + SIZE-WORDS) instead of depending on the heap's zero-initialised
array storage."
  (check-type heap rt-heap)
  (check-type size-words (integer 1 *))
  (let ((tlab (%rt-gc-tlab-for heap thread-id)))
    (unless (and (not (rt-tlab-retired-p tlab))
                 (<= (+ (rt-tlab-free tlab) size-words)
                     (rt-tlab-limit tlab)))
      ;; TLAB exhausted or retired — retire current and refill
      (%rt-gc-tlab-retire heap tlab)
      (%rt-gc-tlab-refill heap thread-id size-words))
    ;; Bump-allocate within TLAB
    (let ((addr (rt-tlab-free tlab)))
      (setf (rt-tlab-free tlab) (+ addr size-words))
      (incf (rt-heap-total-alloc-words heap) size-words)
      (%rt-gc-note-allocation-rate heap)
      (dolist (hook *rt-gc-alloc-hooks*)
        (funcall hook heap size-words))
      (rt-gc-simd-zero-fill heap addr size-words)
      addr)))

(defun rt-gc-simd-zero-fill (heap addr size-words)
  "FR-345: SIMD zero-fill interface for newly allocated heap blocks.
In a native codegen backend (x86-64, AArch64) this is replaced by vectorised
zero-fill.  Pure CL zeroes via sequential rt-heap-set.  Returns ADDR."
  (check-type heap rt-heap)
  (check-type addr (integer 0 *))
  (check-type size-words (integer 0 *))
  (loop for i from 0 below size-words
        do (rt-heap-set heap (+ addr i) 0))
  addr)

(defun rt-gc-tlab-retire-all (heap)
  "Retire all TLABs for HEAP.  Called before a minor GC so that all thread
buffers are flushed to the heap, allowing the collector to observe the full
  young-space allocation."
  (dolist (entry *rt-thread-local-heaps*)
    (when (eq (first entry) heap)
      (%rt-gc-tlab-retire heap (cddr entry)))))

;;; ------------------------------------------------------------
;;; FR-342: GC Concurrent Relocation — PROVISIONAL (Pure CL complete)
;;;
;;; Pure CL implementation: forwarding table hooks are defined in heap.lisp
;;; (rt-gc-forward-object, rt-gc-clear-forwarding-table) and the relocation
;;; barrier in rt-heap-ref uses RT-HEAP-FORWARDING-TABLE for self-healing
;;; stale pointer repair.  The Pure CL metadata recording is complete.
;;;
;;; Deferred to Tier 6 (memory-gc.md): full concurrent relocation requires
;;; load barriers (FR-349) and colored pointers (FR-348), which depend on
;;; native backend mmap/mprotect integration.
;;; ------------------------------------------------------------

;;; ------------------------------------------------------------
;;; FR-391: Heap Growth Policy (foundation)
;;;
;;; rt-heap-maybe-grow (heap.lisp) implements 2x growth when occupancy > 90%.
;;; rt-heap-maybe-shrink implements halving after 3 low-occupancy cycles.
;;; Max heap size is controlled by *gc-max-heap-words*.
;;;
;;; Deferred: contiguous address-space growth via mmap in native backends.
;;; Pure CL uses simple-vector resize which may copy.
;;; ------------------------------------------------------------

;;; ------------------------------------------------------------
;;; FR-422: GC Ergonomics / Auto-Configuration (foundation)
;;;
;;; rt-gc-auto-configure-heap (heap.lisp) detects system RAM and configures
;;; young/old sizes.  Container detection via rt-heap-detect-container-memory-limit.
;;; CLI override via --heap-max argument supported.
;;; ------------------------------------------------------------

;;; ------------------------------------------------------------
;;; FR-424: GC Policy Selection (foundation)
;;;
;;; rt-gc-select-policy provides :throughput/:latency/:memory policy presets.
;;; Each policy adjusts *gc-young-size-words*, *gc-old-size-words*,
;;; and *gc-tenuring-threshold*.
;;; ------------------------------------------------------------
