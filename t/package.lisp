;;;; t/package.lisp — cl-cc-runtime test package.

(defpackage :cl-cc-runtime/test
  (:use :cl :cl-weave :cl-cc/runtime)
  (:shadowing-import-from :cl-weave #:describe))

(in-package :cl-cc-runtime/test)
