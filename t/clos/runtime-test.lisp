(in-package :cl-cc/runtime/clos/test)

(it-sequential
  "With no method stack: rt-next-method-p returns nil; rt-call-next-method signals error."
  (expect (cl-cc/runtime::rt-next-method-p) :to-be-falsy)
  (signals error (cl-cc/runtime::rt-call-next-method)))
