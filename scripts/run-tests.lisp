;;;; run-tests.lisp — load :cl-cc-runtime-test and run the cl-weave suite.
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
       (%runtime-dep-tree "CL_CC_RUNTIME_CL_WEAVE_ROOT")
       (%runtime-dep-tree "CL_CC_RUNTIME_CL_LOG_KIT_ROOT")
       (%runtime-dep-tree "CL_CC_RUNTIME_CL_PROCESS_KIT_ROOT")
       (%runtime-dep-tree "CL_CC_RUNTIME_CL_BOUNDARY_KIT_ROOT")
       (%runtime-dep-tree "CL_CC_RUNTIME_CL_JSON_KIT_ROOT")
       :inherit-configuration))
(handler-case (asdf:load-system :cl-cc-runtime-test)
  (error (e) (format t "~&FAIL load: ~a~%" e) (finish-output) (sb-ext:exit :code 1)))
(if (funcall (find-symbol "RUN-ALL" :cl-weave) :reporter :spec :pass-with-no-tests nil)
    (progn (format t "~&RESULT: ALL PASS~%") (finish-output))
    (progn (format t "~&RESULT: FAIL~%") (finish-output) (sb-ext:exit :code 1)))
