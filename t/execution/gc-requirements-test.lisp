(in-package :cl-cc/runtime/execution/test)

(it-sequential "FR-376: rt-install-stack-guard fails until native guard pages are wired." (signals error (cl-cc/runtime::rt-install-stack-guard 0 4096)))

(it-sequential-each (("rt-install-stack-guard" cl-cc/runtime::rt-install-stack-guard))
    "FR-376: Pure CL execution interface entry point ~A is fbound."
    (label sym)
  (declare (ignore label))
  (expect (fboundp sym) :to-be-truthy))
