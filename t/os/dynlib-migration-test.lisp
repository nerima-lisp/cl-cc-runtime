;;;; Dynamic library public API migration coverage

(in-package :cl-cc/runtime/os/test)

#+darwin
(it-sequential "dynlib-load-foundation-framework"
  (let ((library (cl-cc/runtime/os:rt-ffi-load-library
                  "/System/Library/Frameworks/Foundation.framework/Foundation"))
        (closed nil))
    (unwind-protect
         (progn
           (expect library :to-be-truthy)
           (expect
             (progn
               (cl-cc/runtime/os:rt-ffi-close-library library)
               (setf closed t)
               t)
             :to-be-truthy))
      (unless closed
        (cl-cc/runtime/os:rt-ffi-close-library library)))))
