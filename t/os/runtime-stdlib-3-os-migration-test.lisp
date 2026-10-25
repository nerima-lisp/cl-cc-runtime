;;;; t/os/runtime-stdlib-3-os-migration-test.lisp
(in-package :cl-cc/runtime/os/test)

;; Running this serially avoids forking while test workers hold heap/malloc
;; locks on macOS.
(it-sequential "rt-process-management-shell-output"
               (expect (cl-cc/runtime/os:rt-shell "printf hello")
                       :to-equal
                       "hello"))
