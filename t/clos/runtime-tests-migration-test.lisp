(in-package :cl-cc/runtime/clos/test)

(it-sequential "rt-next-method-absent"
  (expect (cl-cc/runtime/clos:rt-next-method-p) :to-be-falsy)
  (signals error (cl-cc/runtime/clos:rt-call-next-method)))
