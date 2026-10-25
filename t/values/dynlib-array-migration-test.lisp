;;;; Pinned array API migration coverage

(in-package :cl-cc/runtime/values/test)

(it-sequential "fr-417-pinned-unboxed-array-provides-data-pointer"
  (let* ((array (make-array 4 :element-type '(unsigned-byte 8)
                            :initial-contents '(1 2 3 4)))
         (buffer (cl-cc/runtime/values:rt-pin-unboxed-array array)))
    (expect (cl-cc/runtime/values:rt-pinned-unboxed-array-buffer-p buffer) :to-be-truthy)
    (expect (cl-cc/runtime/values:rt-pinned-unboxed-array-buffer-array buffer) :to-be array)
    (expect (= 4 (cl-cc/runtime/values:rt-pinned-unboxed-array-buffer-length buffer)) :to-be-truthy)
    (expect (cl-cc/runtime/values:rt-pinned-array-data-pointer buffer) :to-be-truthy)
    (cl-cc/runtime/values:rt-release-pinned-array buffer)
    (expect (cl-cc/runtime/values:rt-pinned-unboxed-array-buffer-released-p buffer) :to-be-truthy)
    (signals error (cl-cc/runtime/values:rt-pinned-array-data-pointer buffer))))

