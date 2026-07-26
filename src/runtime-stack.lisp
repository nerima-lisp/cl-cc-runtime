;;;; runtime-stack.lisp — Call-depth guard, return-address poisoning, OOM/GC-pressure conditions
(in-package :cl-cc/runtime)

(defparameter *max-call-stack-depth* 10000
  "Maximum native/runtime logical call stack depth before stack overflow.")

(defvar *rt-call-stack-depth* 0
  "Current logical runtime call depth for stack guard instrumentation.")

(define-condition rt-stack-overflow (storage-condition)
  ((depth :initarg :depth :reader rt-stack-overflow-depth)
   (limit :initarg :limit :reader rt-stack-overflow-limit))
  (:report (lambda (c s)
             (format s "Runtime stack overflow at depth ~D (limit ~D)"
                     (rt-stack-overflow-depth c)
                     (rt-stack-overflow-limit c)))))

(define-condition rt-oom-condition (storage-condition)
  ((requested-words :initarg :requested-words :reader rt-oom-requested-words)
   (limit-words :initarg :limit-words :reader rt-oom-limit-words)
   (used-words :initarg :used-words :reader rt-oom-used-words))
  (:report (lambda (c s)
             (format s "Runtime heap exhausted: requested ~D words, used ~D, limit ~D"
                     (rt-oom-requested-words c)
                     (rt-oom-used-words c)
                     (rt-oom-limit-words c)))))

(define-condition rt-gc-pressure-warning (warning)
  ((heap :initarg :heap :reader rt-gc-pressure-warning-heap)
   (occupancy :initarg :occupancy :reader rt-gc-pressure-warning-occupancy)
   (threshold :initarg :threshold :reader rt-gc-pressure-warning-threshold))
  (:report (lambda (c s)
             (format s "Runtime heap pressure ~,1F% crossed ~D% threshold"
                     (rt-gc-pressure-warning-occupancy c)
                     (rt-gc-pressure-warning-threshold c)))))

(defconstant +rt-return-address-poison-mask+ #x5afe000000000000
  "High-bit poison mask used to tag VM/runtime return addresses.")

(defun rt-poison-return-address (return-address)
  "Tag RETURN-ADDRESS so accidental use as an object/code pointer is detectable."
  (check-type return-address integer)
  (logxor return-address +rt-return-address-poison-mask+))

(defun rt-unpoison-return-address (poisoned-address)
  "Recover the original return address from POISONED-ADDRESS."
  (check-type poisoned-address integer)
  (logxor poisoned-address +rt-return-address-poison-mask+))

(defun rt-return-address-poisoned-p (value)
  "Return true when VALUE carries the runtime return-address poison tag."
  (and (integerp value)
       (= (logand value +rt-return-address-poison-mask+)
          +rt-return-address-poison-mask+)))

(defun rt-check-stack-overflow (&optional (depth *rt-call-stack-depth*))
  "Signal RT-STACK-OVERFLOW when DEPTH reaches *MAX-CALL-STACK-DEPTH*."
  (when (>= depth *max-call-stack-depth*)
    (error 'rt-stack-overflow :depth depth :limit *max-call-stack-depth*))
  depth)

(defmacro rt-with-call-stack-guard (() &body body)
  "Run BODY with runtime call-depth accounting and stack overflow guard."
  `(let ((*rt-call-stack-depth* (1+ *rt-call-stack-depth*)))
     (rt-check-stack-overflow)
     ,@body))

(defun rt-signal-oom (requested-words &key heap (limit-words nil) (used-words nil))
  "Signal a STORAGE-CONDITION for runtime out-of-memory paths."
  (error 'rt-oom-condition
         :requested-words requested-words
         :limit-words (or limit-words (and heap (rt-heap-max-heap-words heap)) 0)
         :used-words (or used-words (and heap (ignore-errors (%rt-heap-live-used-words heap))) 0)))

(defun rt-check-heap-pressure-thresholds (heap)
  "Warn at fixed 80/90/95% heap pressure thresholds and return occupancy." 
  (let ((occupancy (rt-heap-occupancy-pct heap)))
    (dolist (threshold '(80 90 95))
      (when (>= occupancy threshold)
        (warn 'rt-gc-pressure-warning
              :heap heap :occupancy occupancy :threshold threshold)))
    occupancy))

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

(defstruct (stack-segment (:constructor make-stack-segment
                            (&key (base 0) (size *stack-segment-size*) next prev
                                  (used 0) guard-page-p)))
  "Logical/native stack segment descriptor for green-thread stacks."
  base
  (size *stack-segment-size* :type integer)
  next
  prev
  (used 0 :type integer)
  guard-page-p)

(defvar *stack-segment-pool* nil
  "Reusable stack segments retired by green threads.")

(defun %reuse-or-make-stack-segment (&key prev (size *stack-segment-size*))
  (let ((segment (or (pop *stack-segment-pool*)
                     (make-stack-segment :size size))))
    (setf (stack-segment-size segment) size
          (stack-segment-used segment) 0
          (stack-segment-prev segment) prev
          (stack-segment-next segment) nil)
    (when prev
      (setf (stack-segment-next prev) segment))
    segment))

(defun grow-stack-segment (segment &key (size *stack-segment-size*))
  "Return a fresh/reused segment linked after SEGMENT."
  (%reuse-or-make-stack-segment :prev segment :size size))

(defun release-stack-segment (segment)
  "Detach SEGMENT and put it back into *STACK-SEGMENT-POOL*."
  (when segment
    (let ((prev (stack-segment-prev segment))
          (next (stack-segment-next segment)))
      (when prev (setf (stack-segment-next prev) next))
      (when next (setf (stack-segment-prev next) prev))
      (setf (stack-segment-next segment) nil
            (stack-segment-prev segment) nil
            (stack-segment-used segment) 0)
      (push segment *stack-segment-pool*)))
  segment)

(defun stack-segment-ensure-space (segment bytes)
  "Ensure SEGMENT has BYTES free, growing a new segment when necessary."
  (check-type bytes (integer 0 *))
  (let ((current (or segment (%reuse-or-make-stack-segment))))
    (if (> (+ (stack-segment-used current) bytes)
           (stack-segment-size current))
        (grow-stack-segment current)
        current)))

(defun stack-segment-note-frame (segment bytes)
  "Account for BYTES in SEGMENT and return the segment that owns the frame."
  (let ((current (stack-segment-ensure-space segment bytes)))
    (incf (stack-segment-used current) bytes)
    current))

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

(defun copying-stack-grow (frames current-size)
  "Double stack size, copy FRAMES, and relocate frame-pointer-like values."
  (let ((new-size (* 2 current-size)))
    (when (> new-size *max-stack-size*)
      (error 'rt-stack-overflow :depth new-size :limit *max-stack-size*))
    (values (relocate-stack-pointers (copy-tree frames) 0 current-size)
            new-size)))
