;;;; Dynamic library public API migration coverage

(in-package :cl-cc/runtime/os/test)

(defun %test-libc-path ()
  #+darwin "/usr/lib/libSystem.B.dylib"
  #+linux "libc.so.6"
  #-(or darwin linux) nil)

(it-sequential "dynlib-load-register-call-libc"
  (let ((path (%test-libc-path)))
    (when path
      (let ((library (cl-cc/runtime/os:rt-ffi-load-library path)))
        (unwind-protect
             (progn
               (expect library :to-be-truthy)
               (expect
                 (string= "getpid"
                          (cl-cc/runtime/os:rt-define-foreign-function "getpid" library nil :int))
                 :to-be-truthy)
               (expect
                 (progn (cl-cc/runtime/os:rt-foreign-funcall "getpid") t)
                 :to-be-truthy)
               (expect
                 (string= "getppid"
                          (cl-cc/runtime/os:rt-define-foreign-function "getppid" library nil :int))
                 :to-be-truthy)
               (expect
                 (progn (cl-cc/runtime/os:rt-foreign-funcall "getppid") t)
                 :to-be-truthy)
               (expect
                 (handler-case
                     (progn
                       (cl-cc/runtime/os:rt-foreign-funcall "cl_cc_dynlib_migration_unregistered_8d4f2")
                       nil)
                   (error () t))
                 :to-be-truthy))
          (cl-cc/runtime/os:rt-ffi-close-library library))))))

(it-sequential "dynlib-defined-function-is-callable"
  (let ((path (%test-libc-path)))
    (when path
      (let ((library (cl-cc/runtime/os:rt-ffi-load-library path)))
        (unwind-protect
             (progn
               (expect
                 (string= "getpid"
                          (cl-cc/runtime/os:rt-define-foreign-function "getpid" library nil :int))
                 :to-be-truthy)
               (expect
                 (progn (cl-cc/runtime/os:rt-foreign-funcall "getpid") t)
                 :to-be-truthy))
          (cl-cc/runtime/os:rt-ffi-close-library library))))))

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
