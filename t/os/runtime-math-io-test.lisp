(in-package :cl-cc/runtime/os/test)

(it-sequential
  "Runtime clock primitives return integer values."
  (expect (integerp (cl-cc/runtime/os:rt-get-universal-time)) :to-be-truthy)
  (expect (integerp (cl-cc/runtime/os:rt-get-internal-real-time)) :to-be-truthy)
  (expect (integerp (cl-cc/runtime/os:rt-get-internal-run-time)) :to-be-truthy))
