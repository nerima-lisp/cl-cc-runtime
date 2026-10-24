;;;; runtime-stack.lisp — Call-depth guard, return-address poisoning, OOM/GC-pressure conditions
(in-package :cl-cc/runtime/concurrency)

;;; ── Segmented and copying stacks (FR-876 / FR-877) ──────────────────────────
;;;
;;; Two strategies for growing a logical stack past its initial allocation.
;;; Segmented growth chains fixed-size segments and recycles them through a
;;; pool, so growing never copies; copying growth doubles the allocation and
;;; relocates frame-pointer-like values into the new range.
;;;
;;; These stayed behind in the cl-cc monorepo when this system was extracted.
;;; cl-cc's FR export test names GROW-STACK-SEGMENT and RELOCATE-STACK-POINTERS
;;; directly, so it went red as soon as cl-cc actually started compiling this
;;; repository rather than its own stale copy.


(defparameter *stack-segment-size* 8192
  "Default logical stack segment size. Native backends map this as an 8KB mmap segment.")

(defparameter *initial-stack-size* 16384
  "Initial copying-stack size used by native stack growth metadata.")

(defparameter *max-stack-size* (* 64 1024 1024)
  "Maximum copying-stack size before RT-STACK-OVERFLOW is signaled.")

(defstruct (stack-segment (:constructor %make-stack-segment (&key base size region next prev (used 0)))) (base 0 :type integer) (size *stack-segment-size* :type integer) region next prev (used 0 :type integer))

(defvar *stack-segment-pool* nil
  "Reusable stack segments retired by green threads.")

(defun %allocate-stack-segment (size) (let* ((mapped-size (rt-page-align (max *stack-segment-size* size))) (region (rt-allocate-anonymous-memory mapped-size))) (%make-stack-segment :base (rt-mmap-region-address region) :size mapped-size :region region)))

(defun %reuse-or-make-stack-segment (&key prev (size *stack-segment-size*)) (let* ((requested-size (max *stack-segment-size* size)) (segment (find-if (lambda (candidate) (>= (stack-segment-size candidate) requested-size)) *stack-segment-pool*))) (if segment (setf *stack-segment-pool* (delete segment *stack-segment-pool* :test #'eq)) (setf segment (%allocate-stack-segment requested-size))) (setf (stack-segment-used segment) 0 (stack-segment-prev segment) prev (stack-segment-next segment) nil) (when prev (setf (stack-segment-next prev) segment)) segment))

(defun grow-stack-segment (segment &key (size *stack-segment-size*)) "Return a fresh/reused mmap segment linked after SEGMENT." (%reuse-or-make-stack-segment :prev segment :size size))

(defun release-stack-segment (segment)
  "Detach SEGMENT and return it to the reusable mmap pool."
  (when segment
    (let ((prev (stack-segment-prev segment))
          (next (stack-segment-next segment)))
      (when prev (setf (stack-segment-next prev) next))
      (when next (setf (stack-segment-prev next) prev))
      (setf (stack-segment-next segment) nil
            (stack-segment-prev segment) nil
            (stack-segment-used segment) 0)
      (pushnew segment *stack-segment-pool* :test #'eq)))
  segment)

(defun release-stack-segment-chain (segment)
  "Release SEGMENT and every predecessor, returning NIL."
  (loop for current = segment then previous
        while current
        for previous = (stack-segment-prev current)
        do (release-stack-segment current))
  nil)

(defun stack-segment-snapshot (segment)
  "Return detached root-to-current (SIZE USED) metadata for SEGMENT."
  (loop for current = segment then (stack-segment-prev current)
        while current
        collect (list (stack-segment-size current)
                      (stack-segment-used current)) into reversed
        finally (return (nreverse reversed))))

(defun stack-segment-restore (snapshot)
  "Allocate an independent segment chain described by SNAPSHOT."
  (let ((current nil))
    (handler-case
        (dolist (entry snapshot current)
          (destructuring-bind (size used) entry
            (check-type size (integer 1 *))
            (check-type used (integer 0 *))
            (when (> used size)
              (error "Stack segment usage ~D exceeds size ~D" used size))
            (let ((next (%reuse-or-make-stack-segment :size size)))
              (setf (stack-segment-prev next) current)
              (when current
                (setf (stack-segment-next current) next))
              (setf (stack-segment-used next) used
                    current next))))
      (error (condition)
        (release-stack-segment-chain current)
        (error condition)))))

(defun stack-segment-ensure-space (segment bytes) "Ensure the downward-growing stack pointer remains above its segment limit." (check-type bytes (integer 0 *)) (let* ((current (or segment (%reuse-or-make-stack-segment))) (stack-pointer (- (+ (stack-segment-base current) (stack-segment-size current)) (stack-segment-used current))) (limit (stack-segment-base current))) (if (< (- stack-pointer bytes) limit) (grow-stack-segment current :size bytes) current)))

(defun stack-segment-note-frame (segment bytes) "Account for BYTES and return the mmap segment that owns the frame." (let ((current (stack-segment-ensure-space segment bytes))) (incf (stack-segment-used current) bytes) current))

(defun stack-segment-release-frame (segment bytes) "Release BYTES from SEGMENT and retire an empty non-root segment." (check-type bytes (integer 0 *)) (unless segment (error "Cannot release a frame without a stack segment")) (when (> bytes (stack-segment-used segment)) (error "Frame size ~D exceeds segment usage ~D" bytes (stack-segment-used segment))) (decf (stack-segment-used segment) bytes) (if (and (zerop (stack-segment-used segment)) (stack-segment-prev segment)) (let ((previous (stack-segment-prev segment))) (release-stack-segment segment) previous) segment))

(defun relocate-stack-pointers (frames old-base new-base)
  "Relocate pointer-like integer slots in FRAMES from OLD-BASE to NEW-BASE."
  (labels ((relocate (value)
             (cond
               ((and (integerp value) (integerp old-base) (integerp new-base)
                     (>= value old-base))
                (+ new-base (- value old-base)))
               ((consp value) (cons (relocate (car value)) (relocate (cdr value))))
               (t value))))
    (mapcar #'relocate frames)))

