;;;; heap-region.lisp -- fixed-size old-space region metadata for mixed GC.
(in-package :cl-cc/runtime)

(defconstant +rt-heap-region-size-words+ (floor (* 1024 1024) 8)
  "Default region size in heap words (one megabyte at eight bytes per word).")

(defstruct (rt-heap-region (:constructor %make-rt-heap-region)
                           (:conc-name rt-heap-region-))
  "Metadata for one contiguous portion of the managed old generation."
  (index 0 :type fixnum)
  (start-word 0 :type fixnum)
  (end-word 0 :type fixnum)
  (generation :old :type keyword)
  (allocated-bytes 0 :type fixnum)
  (live-bytes 0 :type fixnum)
  (garbage-ratio 0.0d0 :type double-float)
  (remembered-set (make-hash-table :test #'eql))
  (selected-p nil :type boolean)
  (evacuation-failed-p nil :type boolean))

(defparameter *rt-region-mixed-collection-enabled-p* nil
  "When true, major collection performs the region selection pass before sweep.")

(defun rt-heap-initialize-regions (heap)
  "Create the old-space region array for HEAP and return HEAP."
  (let* ((size (max 1 (rt-heap-region-size-words heap)))
         (old-size (rt-heap-old-size heap))
         (count (ceiling old-size size))
         (regions (make-array count)))
    (dotimes (index count)
      (let* ((start (+ (rt-heap-old-base heap) (* index size)))
             (end (min (+ start size) (+ (rt-heap-old-base heap) old-size))))
        (setf (aref regions index)
              (%make-rt-heap-region :index index :start-word start :end-word end))))
    (setf (rt-heap-regions heap) regions)
    heap))

(defun rt-heap-region-for-address (heap address)
  "Return the old-space region containing ADDRESS, or NIL."
  (let ((base (rt-heap-old-base heap))
        (size (rt-heap-region-size-words heap))
        (regions (rt-heap-regions heap)))
    (when (and (plusp size) regions (>= address base)
               (< address (+ base (rt-heap-old-size heap))))
      (aref regions (floor (- address base) size)))))
