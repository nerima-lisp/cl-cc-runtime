(in-package :cl-cc/runtime/os/infra)

(defun %rt-os-allocate-pinned-array (array)
  (let* ((length (length array))
         (allocation (sb-alien:make-alien sb-alien:unsigned-char (max 1 length)))
         (retained-p nil))
    (unwind-protect
         (let ((data-pointer (sb-alien:alien-sap allocation)))
           (loop for index below length
                 do (setf (sb-sys:sap-ref-8 data-pointer index)
                          (aref array index)))
           (multiple-value-prog1 (values allocation data-pointer)
             (setf retained-p t)))
      (unless retained-p
        (sb-alien:free-alien allocation)))))

(defun %rt-os-release-pinned-array (array length allocation data-pointer)
  (unwind-protect
       (loop for index below length
             do (setf (aref array index)
                      (sb-sys:sap-ref-8 data-pointer index)))
    (sb-alien:free-alien allocation))
  (values))

(defun %rt-os-dispose-pinned-array (allocation)
  (sb-alien:free-alien allocation))

(eval-when (:load-toplevel :execute) (rt-register-pinned-array-backend #'%rt-os-allocate-pinned-array #'%rt-os-release-pinned-array #'%rt-os-dispose-pinned-array))
