;;;; value-pinned-array.lisp — Pinned unboxed-array buffers for FFI, split out
;;;; of value.lisp. Loads after value-codec.lisp for encode-pointer/
;;;; decode-pointer.
(in-package :cl-cc/runtime)

;;; Encode/decode codecs (encode-fixnum, decode-fixnum, encode-double,
;;; decode-double, encode-pointer, decode-pointer, pointer-tag,
;;; encode-char, decode-char, encode-bool, cl-value->val, val->cl-value)
;;; are in value-codec.lisp (loaded next).

;;; ── Pinned arrays for FFI (FR-417) ──

(defstruct (rt-pinned-unboxed-array-buffer (:constructor %make-pinned-buffer))
  (array nil :type (simple-array (unsigned-byte 8) (*)))
  (length 0 :type fixnum)
  (allocation nil)
  (data-pointer nil)
  (released-p nil)
  (lock (sb-thread:make-mutex :name "pinned unboxed array buffer")))

(defun rt-pin-unboxed-array (array)
  "Copy ARRAY into foreign memory and return a buffer with a stable FFI pointer.
Writes through the pointer are copied back to ARRAY when the buffer is released."
  (check-type array (simple-array (unsigned-byte 8) (*)))
  (let* ((length (length array))
         (allocation (sb-alien:make-alien sb-alien:unsigned-char (max 1 length)))
         (retained-p nil))
    (unwind-protect
         (let ((data-pointer (sb-alien:alien-sap allocation)))
           (loop for index below length
                 do (setf (sb-sys:sap-ref-8 data-pointer index)
                          (aref array index)))
           (prog1 (%make-pinned-buffer :array array
                                       :length length
                                       :allocation allocation
                                       :data-pointer data-pointer
                                       :released-p nil)
             (setf retained-p t)))
      (unless retained-p
        (sb-alien:free-alien allocation)))))

(defun rt-release-pinned-array (buffer)
  "Copy foreign writes back and free BUFFER. Concurrent releases are serialized."
  (check-type buffer rt-pinned-unboxed-array-buffer)
  (sb-thread:with-mutex ((rt-pinned-unboxed-array-buffer-lock buffer))
    (unless (rt-pinned-unboxed-array-buffer-released-p buffer)
      (let ((array (rt-pinned-unboxed-array-buffer-array buffer))
            (length (rt-pinned-unboxed-array-buffer-length buffer))
            (data-pointer (rt-pinned-unboxed-array-buffer-data-pointer buffer))
            (allocation (rt-pinned-unboxed-array-buffer-allocation buffer)))
        (unwind-protect
             (loop for index below length
                   do (setf (aref array index)
                            (sb-sys:sap-ref-8 data-pointer index)))
          (setf (rt-pinned-unboxed-array-buffer-released-p buffer) t
                (rt-pinned-unboxed-array-buffer-allocation buffer) nil
                (rt-pinned-unboxed-array-buffer-data-pointer buffer) nil)
          (sb-alien:free-alien allocation))))
    (values)))

(defun rt-pinned-array-data-pointer (buffer)
  "Return BUFFER pointer. Callers must finish using it before release."
  (check-type buffer rt-pinned-unboxed-array-buffer)
  (sb-thread:with-mutex ((rt-pinned-unboxed-array-buffer-lock buffer))
    (when (rt-pinned-unboxed-array-buffer-released-p buffer)
      (error "Pinned array buffer has already been released."))
    (or (rt-pinned-unboxed-array-buffer-data-pointer buffer)
        (error "Pinned array data pointer is unavailable on this implementation."))))
