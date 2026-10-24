(defpackage #:cl-cc/runtime/dynamic-binding
  (:use #:cl)
  (:intern
   #:*rt-special-variable-metadata*
   #:rt-dynamic-bind
   #:rt-dynamic-unbind
   #:rt-register-special-variable
  )
  (:export
   #:rt-boundp
   #:rt-make-symbol
   #:rt-makunbound
   #:rt-set-symbol-value
   #:rt-symbol-value
   #:rt-with-dynamic-binding #:*rt-dynamic-binding-stacks* #:*rt-global-var-registry* #:rt-special-variable-global-only-p))



