(in-package :cl-cc/runtime/clos/test)

(it-sequential
  "With no method stack: rt-next-method-p returns nil; rt-call-next-method signals error."
  (expect (cl-cc/runtime/clos:rt-next-method-p) :to-be-falsy)
  (signals error (cl-cc/runtime/clos:rt-call-next-method)))
