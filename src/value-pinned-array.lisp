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
  (data-pointer nil)
  (released-p nil))

(defun rt-pin-unboxed-array (array)
  "Pin ARRAY (a SIMPLE-ARRAY of (UNSIGNED-BYTE 8)) for FFI access.
Returns an RT-PINNED-UNBOXED-ARRAY-BUFFER holding a stable data pointer."
  (check-type array (simple-array (unsigned-byte 8) (*)))
  (let ((buf (%make-pinned-buffer :array array
                                   :length (length array)
                                   :data-pointer (sb-sys:vector-sap array)
                                   :released-p nil)))
    buf))

(defun rt-release-pinned-array (buffer)
  "Release the pinned array BUFFER. After release, data pointer is no longer valid."
  (check-type buffer rt-pinned-unboxed-array-buffer)
  (setf (rt-pinned-unboxed-array-buffer-released-p buffer) t
        (rt-pinned-unboxed-array-buffer-data-pointer buffer) nil)
  (values))

(defun rt-pinned-array-data-pointer (buffer)
  "Return the stable data pointer of BUFFER while it is pinned.
Signals an error if the buffer has been released."
  (check-type buffer rt-pinned-unboxed-array-buffer)
  (when (rt-pinned-unboxed-array-buffer-released-p buffer)
    (error "Pinned array buffer has already been released."))
  (or (rt-pinned-unboxed-array-buffer-data-pointer buffer)
      (error "Pinned array data pointer is unavailable on this implementation.")))
