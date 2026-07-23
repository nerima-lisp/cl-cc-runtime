;;;; run-tests.lisp — load :cl-cc-runtime-test and run the cl-weave suite.
(require :asdf)
(let ((weave (uiop:getenv "CL_CC_RUNTIME_CL_WEAVE_ROOT")))
  (unless weave
    (format t "~&FAIL: CL_CC_RUNTIME_CL_WEAVE_ROOT is not set~%") (finish-output)
    (sb-ext:exit :code 1))
  (asdf:initialize-source-registry
   (list :source-registry (list :tree (truename ".")) (list :tree (truename weave))
         :inherit-configuration)))
(handler-case (asdf:load-system :cl-cc-runtime-test)
  (error (e) (format t "~&FAIL load: ~a~%" e) (finish-output) (sb-ext:exit :code 1)))
(if (funcall (find-symbol "RUN-ALL" :cl-weave) :reporter :spec :pass-with-no-tests nil)
    (progn (format t "~&RESULT: ALL PASS~%") (finish-output))
    (progn (format t "~&RESULT: FAIL~%") (finish-output) (sb-ext:exit :code 1)))
