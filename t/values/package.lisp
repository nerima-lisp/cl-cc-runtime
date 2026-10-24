(defpackage :cl-cc/runtime/values/test
  (:use :cl :cl-weave :cl-cc/runtime/values)
  (:shadowing-import-from :cl-cc/runtime/values #:make-hash-table)
  (:shadowing-import-from :cl-weave #:describe))
