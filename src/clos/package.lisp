(defpackage #:cl-cc/runtime/clos
  (:use #:cl)
  (:import-from #:cl-cc/runtime/execution #:rt-code-cache-evict-class)
  (:import-from #:cl-cc/runtime/memory #:%rt-gc-heap-reference-count #:rt-gc-register-post-sweep-hook #:rt-heap)
  (:intern
   #:%rt-classify-arg
   #:%rt-cpl-walk
   #:%rt-eql-specializer-p
   #:%rt-extract-eql-specializer-keys
   #:*rt-primitive-type-classifiers*
  )
  (:export
   #:*rt-class-registry*
   #:*rt-generic-function-registry*
   #:*rt-method-context-stack*
   #:rt-call-generic
   #:rt-call-next-method
   #:rt-class-name
   #:rt-class-of
   #:rt-compute-applicable-methods
   #:rt-defclass
   #:rt-find-class
   #:rt-make-instance
   #:rt-make-instance-0
   #:rt-next-method-p
   #:rt-register-method
   #:rt-slot-boundp
   #:rt-slot-exists-p
   #:rt-slot-makunbound
   #:rt-slot-set
   #:rt-slot-value))



