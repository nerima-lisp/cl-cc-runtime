;;;; run-coverage.lisp — instrument :cl-cc-runtime with sb-cover, run the
;;;; cl-weave suite, and write an HTML + summary report under coverage/.
;;;;
;;;; Uses the same CL_CC_RUNTIME_<NAME>_ROOT source-registry convention as
;;;; scripts/run-tests.lisp.

(require :asdf)
(require :sb-cover)

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

(declaim (optimize sb-cover:store-coverage-data))
(handler-case (asdf:oos 'asdf:load-op :cl-cc-runtime :force t)
  (error (e) (format t "~&FAIL load cl-cc-runtime: ~a~%" e) (finish-output) (sb-ext:exit :code 1)))

(declaim (optimize (sb-cover:store-coverage-data 0)))
(handler-case (asdf:load-system :cl-cc-runtime-test)
  (error (e) (format t "~&FAIL load cl-cc-runtime-test: ~a~%" e) (finish-output) (sb-ext:exit :code 1)))

(funcall (find-symbol "RUN-ALL" :cl-weave) :reporter :spec :pass-with-no-tests nil)

(ensure-directories-exist "coverage/")
(sb-cover:report "coverage/")
(format t "~&Coverage report written to coverage/cover-index.html~%")
(finish-output)
