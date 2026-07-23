;;;; run-compile-check.lisp
;;;;
;;;; Compile and load :cl-cc-runtime from the current source tree, then exit
;;;; non-zero on any compile/load error. This is the build and CI gate for a
;;;; dependency-free leaf system, so no external source registry is required
;;;; beyond the project root registered below.

(require :asdf)

(asdf:initialize-source-registry
 (list :source-registry
       (list :tree (truename "."))
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
