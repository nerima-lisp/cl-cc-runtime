(defpackage #:cl-cc/runtime/execution
  (:use #:cl)
  (:intern
   #:*max-call-stack-depth*
   #:*rt-call-stack-depth*
   #:make-rt-code-cache
  )
  (:export
   #:*rt-code-cache*
   #:rt-apply-fn
   #:rt-call-fn
   #:rt-check-stack-overflow
   #:rt-closure-obj
   #:rt-closure-obj-p
   #:rt-closure-ref
   #:rt-code-cache-evict
   #:rt-code-cache-evict-class
   #:rt-code-cache-lookup
   #:rt-code-cache-stats
   #:rt-code-cache-store
   #:rt-functionp
   #:rt-gc-unload-code
   #:rt-make-closure
   #:rt-poison-return-address
   #:rt-register-function
   #:rt-register-stack-overflow-signaler
   #:rt-return-address-poisoned-p
   #:rt-unpoison-return-address
   #:rt-with-call-stack-guard))



