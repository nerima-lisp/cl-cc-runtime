;;;; gc-alloc.lisp — Young/old bump allocation and root registration tuning
;;;; constants, split out of gc-roots-objects.lisp
(in-package :cl-cc/runtime)

;; Ensure the card-size constant is present even if this file is compiled or
;; loaded in isolation during incremental builds.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (boundp '*gc-tenuring-threshold*)
    (defparameter *gc-tenuring-threshold* 3
      "Minor GC survival cycles before promotion to old generation."))
  (unless (boundp '+gc-card-size-words+)
    (defconstant +gc-card-size-words+ 64
      "Card size in words (512 bytes with 8-byte words).")))

;;; ------------------------------------------------------------
;;; Section 1: Allocation
;;; ------------------------------------------------------------

(defun %rt-gc-old-space-allocation-p (type-tag)
  "Return true when TYPE-TAG explicitly requests old-generation allocation."
  (member type-tag '(:old :old-space :old-generation :tenured) :test #'eq))

(defun %rt-gc-alloc-old-bump (heap size-words)
  "Allocate SIZE-WORDS words from old-space using the bump pointer."
  (let* ((addr (rt-heap-old-free heap))
         (limit (+ (rt-heap-old-base heap) (rt-heap-old-size heap))))
    (when (> (+ addr size-words) limit)
      (if (fboundp 'rt-signal-oom)
          (rt-signal-oom size-words :heap heap :limit-words limit :used-words addr)
          (error "cl-cc/runtime: old space exhausted — ~D words requested" size-words)))
    (%rt-ensure-compressed-pointer-range addr size-words)
    (setf (rt-heap-old-free heap) (+ addr size-words))
    addr))

;; Hoisted to a parameter: inlined at its call site the control string alone
;; runs past the 100-column limit, and it must stay one string literal.
(defparameter +rt-young-space-oom-format+
  "cl-cc/runtime: heap exhausted — ~D words requested, ~D words available in young space")

(defun %rt-gc-alloc-via-slab (heap slab-class size-words)
  "Try slab allocation for SLAB-CLASS. Returns NIL on exhaustion (the slab
page grows into old space, which can itself be full) so the caller falls
back to another allocation strategy instead of propagating the error."
  (handler-case
      (let ((addr (rt-slab-alloc heap slab-class)))
        (%rt-ensure-compressed-pointer-range addr size-words)
        (rt-gc-profile-sample (* size-words 8))
        addr)
    (error () nil)))

(defun %rt-gc-alloc-large-object (heap size-words)
  "FR-086: Large Object Space (LOS) — allocate SIZE-WORDS directly in
large-object space, bypassing the nursery, for objects past the threshold."
  (let* ((addr (rt-heap-large-obj-free heap))
         (limit (+ (rt-heap-large-obj-base heap)
                   (rt-heap-large-obj-size heap))))
    (when (> (+ addr size-words) limit)
      (if (fboundp 'rt-signal-oom)
          (rt-signal-oom size-words :heap heap :limit-words limit :used-words addr)
          (error "cl-cc/runtime: large object space exhausted — ~D words requested"
                 size-words)))
    (%rt-ensure-compressed-pointer-range addr size-words)
    (setf (rt-heap-large-obj-free heap) (+ addr size-words))
    (rt-gc-profile-sample (* size-words 8))
    addr))

(defun %rt-gc-alloc-old-space (heap size-words)
  "Allocate SIZE-WORDS words for an explicitly old-generation TYPE-TAG,
reusing a free-list block of the right size when one is available."
  (multiple-value-bind (class-size free-list-addr)
      (rt-free-list-alloc-from-bin heap size-words)
    (let* ((alloc-size (or class-size size-words))
           (addr (or free-list-addr
                     (%rt-gc-alloc-old-bump heap alloc-size))))
      (rt-gc-profile-sample (* alloc-size 8))
      addr)))

(defun %rt-gc-alloc-young-space (heap size-words)
  "Bump-allocate SIZE-WORDS words in young from-space, triggering a minor GC
and retrying once when the space is exhausted."
  (let* ((from-base (rt-heap-young-from-base heap))
         (semi-size (rt-heap-young-semi-size heap))
         (limit     (+ from-base semi-size))
         (addr      (rt-heap-young-free heap)))
    (when (> (+ addr size-words) limit)
      (if (rt-heap-gc-inhibit heap)
          (setf (rt-heap-gc-pending heap) t)
          (rt-gc-minor-collect heap))
      ;; Recompute after GC (bases may have flipped)
      (setf from-base (rt-heap-young-from-base heap)
            limit     (+ from-base semi-size)
            addr      (rt-heap-young-free heap))
      (when (> (+ addr size-words) limit)
        (if (fboundp 'rt-signal-oom)
            (rt-signal-oom size-words :heap heap :limit-words limit :used-words addr)
            (error +rt-young-space-oom-format+
                   size-words (- limit addr)))))
    (%rt-ensure-compressed-pointer-range addr size-words)
    (setf (rt-heap-young-free heap) (+ addr size-words))
    (rt-gc-profile-sample (* size-words 8))
    addr))

(defun rt-gc-alloc (heap type-tag size-words)
  "Allocate SIZE-WORDS words and return the word address. TYPE-TAG selects
   allocation policy/slab class. Object headers are FR-266 compressed
   one-word headers built with MAKE-RT-HEADER, but the header is NOT written
   here; the caller is responsible for writing it immediately after
   allocation, optionally embedding an FR-214 shape id. Automatically
   triggers a minor GC if from-space is exhausted. Signals an error if the
   heap is exhausted even after GC.

   Dispatches to one of four strategies, in order: a slab pool for
   TYPE-TAG/SIZE-WORDS (falling through to the next strategy if the slab
   page itself cannot grow), large-object space (FR-086, past the size
   threshold), the old-generation free-list/bump allocator (for an
   explicitly old-generation TYPE-TAG), or young-space bump allocation (the
   default)."
  (rt-gc-safepoint-check heap :kind :allocation)
  (rt-gc-pacer-maybe-throttle heap size-words)
  (%rt-gc-enforce-heap-limit heap size-words)
  (incf (rt-heap-total-alloc-words heap) size-words)
  (%rt-gc-note-allocation-rate heap)
  (dolist (hook *rt-gc-alloc-hooks*)
    (funcall hook heap size-words))
  ;; The allocator returns an uninitialized object whose compressed header is
  ;; written by the caller.  Stress mode therefore collects immediately before
  ;; each allocation, exercising GC on every allocation boundary without
  ;; evacuating a headerless object that has not yet been installed by the caller.
  (when (and *gc-stress-mode*
             (not (rt-heap-gc-inhibit heap))
             (eq (rt-heap-gc-state heap) :normal)
             (> (rt-heap-young-free heap) (rt-heap-young-from-base heap)))
    (rt-gc-minor-collect heap))
  (let ((slab-class (and *rt-use-slab-allocator*
                          (rt-slab-size-class type-tag size-words))))
    (or (and slab-class (%rt-gc-alloc-via-slab heap slab-class size-words))
        (cond
          ((> size-words (rt-heap-large-obj-threshold heap))
           (%rt-gc-alloc-large-object heap size-words))
          ((%rt-gc-old-space-allocation-p type-tag)
           (%rt-gc-alloc-old-space heap size-words))
          (t
           (%rt-gc-alloc-young-space heap size-words))))))
