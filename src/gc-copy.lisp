;;;; gc-copy.lisp — Cheney-scan object copying (%gc-copy-object,
;;;; %gc-ensure-copied) used by the minor-GC scanner in gc-minor.lisp, split
;;;; out of gc-tlab.lisp
(in-package :cl-cc/runtime)

(defun %rt-gc-normalize-address (addr)
  (if (and (integerp addr) (val-pointer-p addr))
      (decode-pointer addr)
      addr))

(defun %rt-gc-copy-co-located-neighbor (heap from-addr to-free-cell promoted-list-cell in-source-p)
  "Copy FROM-ADDR's co-location neighbor next when it is still in the source set."
  (let* ((hints (rt-heap-co-location-hints heap))
         (neighbor (and hints (gethash from-addr hints))))
    (when neighbor
      ;; One-shot consumption avoids recursive ping-pong while preserving adjacency.
      (remhash from-addr hints)
      (remhash neighbor hints)
      (when (and in-source-p
                 (integerp neighbor)
                 (/= neighbor from-addr)
                 (funcall in-source-p neighbor))
        (let ((neighbor-header (rt-heap-object-header heap neighbor)))
          (unless (header-forwarding-p neighbor-header)
            (multiple-value-bind (neighbor-dest neighbor-free)
                (%gc-copy-object heap neighbor (cdr to-free-cell) promoted-list-cell)
              (declare (ignore neighbor-dest))
              (setf (cdr to-free-cell) neighbor-free))))))))

(defun %gc-copy-object (heap from-addr to-free promoted-list-cell)
  "Copy the object at FROM-ADDR to TO-FREE, or to old space if promotion applies.
   When promoted, push the destination old-space address onto (car PROMOTED-LIST-CELL)
   so the caller can later scan those objects for old->young pointers.
   Installs a forwarding pointer (cons :forwarded dest) at FROM-ADDR slot 0.
   Returns (values new-addr new-to-free)."
  (let* ((header    (rt-heap-object-header heap from-addr))
         (size      (rt-header-size header))
         (age       (rt-header-age header))
         (pinned-p  (rt-object-pinned-p heap from-addr))
          ;; Header age is a 2-bit saturating field (0..3).  Dynamic tenure may
          ;; temporarily raise the threshold above that representable maximum; in
          ;; that case an age-saturated object must still be promotable.
          (effective-threshold (min 3 *gc-tenuring-threshold*))
          (promote-p (or pinned-p (>= age effective-threshold))))
    (let ((dest-addr
            (if promote-p
                ;; Promote to old space, reusing sweep free-list blocks first.
                (or (%rt-gc-alloc-old-from-free-list heap size)
                    (let ((old-free (rt-heap-old-free heap)))
                      (when (>= (+ old-free size)
                                (+ (rt-heap-old-base heap) (rt-heap-old-size heap)))
                        (error "cl-cc/runtime: old space exhausted during promotion"))
                      (setf (rt-heap-old-free heap) (+ old-free size))
                      old-free))
                ;; Copy to to-space
                to-free)))
      ;; Copy all words verbatim
      (loop for i from 0 below size do
        (rt-heap-set heap (+ dest-addr i)
                     (rt-heap-ref heap (+ from-addr i))))
      ;; Increment age in the destination header
      (rt-heap-set-header heap dest-addr
                           (rt-header-increment-age header))
      (let ((new-age (rt-header-age (rt-heap-object-header heap dest-addr))))
        (incf (svref (rt-heap-age-hist heap) new-age)))
      ;; Install forwarding pointer in source slot 0
      (rt-heap-set-header heap from-addr
                          (header-make-forwarding-ptr dest-addr))
      ;; Track promoted objects for later card-dirtying pass
      (when promote-p
        (push dest-addr (car promoted-list-cell))
        (setf (gethash dest-addr (rt-heap-recent-promotions heap))
              (rt-heap-minor-gc-count heap))
        (incf (rt-heap-words-promoted heap) size)
        (when pinned-p
          (rt-unpin-object heap from-addr)
          (rt-pin-object heap dest-addr)))
      ;; Return new address and updated to-free
      (values dest-addr
              (if promote-p to-free (+ to-free size))))))

(defun %gc-ensure-copied (heap from-addr to-free-cell promoted-list-cell &optional in-source-p)
  "Ensure the object at FROM-ADDR has been copied to to-space or old space.
    Returns the new (destination) address.
    Updates (cdr TO-FREE-CELL) in place when a new copy is made in to-space."
  (when (and (integerp from-addr) (val-pointer-p from-addr))
    (setf from-addr (decode-pointer from-addr)))
  (unless (integerp from-addr)
    (error "cl-cc/runtime: GC copy requested for non-pointer value ~S" from-addr))
  (let ((h (rt-heap-object-header heap from-addr)))
    (cond
      ((header-forwarding-p h)
       ;; Already copied — return existing forwarding destination
       (header-forwarding-ptr h))
      (t
        (multiple-value-bind (new-addr new-free)
            (%gc-copy-object heap from-addr (cdr to-free-cell) promoted-list-cell)
          (setf (cdr to-free-cell) new-free)
          (%rt-gc-copy-co-located-neighbor heap from-addr to-free-cell
                                           promoted-list-cell in-source-p)
          new-addr)))))
