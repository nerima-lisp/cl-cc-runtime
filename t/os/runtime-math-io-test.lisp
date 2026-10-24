(in-package :cl-cc/runtime/os/test)

(it-sequential
  "Runtime clock primitives return positive integers."
  (expect (integerp (cl-cc/runtime::rt-get-universal-time)) :to-be-truthy)
  (expect (integerp (cl-cc/runtime::rt-get-internal-real-time)) :to-be-truthy)
  (expect (integerp (cl-cc/runtime::rt-get-internal-run-time)) :to-be-truthy))
