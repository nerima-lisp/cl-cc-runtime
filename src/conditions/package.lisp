(defpackage #:cl-cc/runtime/conditions
  (:use #:cl)
  (:import-from #:cl-cc/runtime/execution #:rt-call-fn #:rt-closure-obj #:rt-closure-obj-p #:rt-register-stack-overflow-signaler)
  (:intern
   #:rt-stack-overflow
   #:rt-stack-overflow-depth
   #:rt-stack-overflow-limit
  )
  (:export
   #:*handler-stack*
   #:*restart-stack*
   #:*rt-debugger-hook*
   #:make-rt-handler
   #:make-rt-restart
   #:rt-arithmetic-error
   #:rt-cell-error
   #:rt-cerror
   #:rt-control-error
   #:rt-dispatch-restart
   #:rt-dispatch-signal
   #:rt-division-by-zero
   #:rt-establish-handler
   #:rt-establish-restart
   #:rt-file-error
   #:rt-find-handler
   #:rt-find-restart
   #:rt-floating-point-overflow
   #:rt-floating-point-underflow
   #:rt-gc-pressure-warning
   #:rt-gc-pressure-warning-heap
   #:rt-gc-pressure-warning-occupancy
   #:rt-gc-pressure-warning-threshold
   #:rt-handler
   #:rt-handler-condition-type
   #:rt-handler-handler-function
   #:rt-handler-p
   #:rt-invoke-debugger-hook
   #:rt-invoke-restart
   #:rt-oom-condition
   #:rt-oom-limit-words
   #:rt-oom-requested-words
   #:rt-oom-used-words
   #:rt-pop-handler
   #:rt-pop-restart
   #:rt-program-error
   #:rt-push-handler
   #:rt-push-restart
   #:rt-restart
   #:rt-restart-bind
   #:rt-restart-case
   #:rt-restart-function
   #:rt-restart-name
   #:rt-restart-p
   #:rt-runtime-condition
   #:rt-runtime-error
   #:rt-serious-condition
   #:rt-signal
   #:rt-signal-error
   #:rt-simple-type-error
   #:rt-storage-condition
   #:rt-stream-error
   #:rt-type-error
   #:rt-unbound-variable
   #:rt-undefined-function
   #:rt-warn-fn
   #:rt-warning
   #:rt-with-debugger-hook #:rt-register-condition-signal-guard #:rt-call-with-condition-signal-guard))



