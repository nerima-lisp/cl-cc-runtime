;;;; run-compile-check.lisp
;;;;
;;;; Compile and load :cl-cc-runtime from the current source tree, then exit
;;;; non-zero on any compile/load error. This is the build and CI gate.
;;;; cl-cc-runtime depends on sibling nerima-lisp libraries (cl-log-kit,
;;;; cl-process-kit, and cl-process-kit's own cl-boundary-kit dependency);
;;;; each is pulled in as a source-only flake input and located here via a
;;;; CL_CC_RUNTIME_<NAME>_ROOT environment variable, the same convention
;;;; run-tests.lisp uses for cl-weave.

(require :asdf)

(defun %runtime-dep-tree (env-var)
  (let ((root (uiop:getenv env-var)))
    (unless root
      (format t "~&FAIL: ~A is not set~%" env-var) (finish-output)
      (sb-ext:exit :code 1))
    (list :tree (truename root))))

(asdf:initialize-source-registry
 (list :source-registry
       (list :tree (truename "."))
       (%runtime-dep-tree "CL_CC_RUNTIME_CL_LOG_KIT_ROOT")
       (%runtime-dep-tree "CL_CC_RUNTIME_CL_PROCESS_KIT_ROOT")
       (%runtime-dep-tree "CL_CC_RUNTIME_CL_BOUNDARY_KIT_ROOT")
       (%runtime-dep-tree "CL_CC_RUNTIME_CL_JSON_KIT_ROOT")
       :inherit-configuration))

(handler-case
    (progn
      (asdf:load-system :cl-cc-runtime)
      (format t "~&PASS cl-cc-runtime compile check~%")
      (finish-output))
  (error (e)
    (format t "~&FAIL cl-cc-runtime: ~a~%" e)
    (finish-output)
    (sb-ext:exit :code 1)))
