(in-package :cl-cc/runtime/dynamic-binding/test)

(defmacro with-fresh-var-registries (&body body)
  `(let ((cl-cc/runtime/dynamic-binding:*rt-global-var-registry* (make-hash-table :test #'eq))
        (*rt-special-variable-metadata* (make-hash-table :test #'eq))
        (cl-cc/runtime/dynamic-binding:*rt-dynamic-binding-stacks* (make-hash-table :test #'equal)))
    ,@body))

(it-sequential
  "rt-set-symbol-value / rt-symbol-value use the runtime global registry."
  (with-fresh-var-registries
    (cl-cc/runtime/dynamic-binding:rt-set-symbol-value 'alpha 11)
    (expect (cl-cc/runtime/dynamic-binding:rt-symbol-value 'alpha) :to-equal 11)
    (expect (cl-cc/runtime/dynamic-binding:rt-boundp 'alpha) :to-equal 1)
    (cl-cc/runtime/dynamic-binding:rt-makunbound 'alpha)
    (expect (cl-cc/runtime/dynamic-binding:rt-boundp 'alpha) :to-equal 0)))

(it-sequential
  "rt-symbol-value signals when the variable was never assigned."
  (with-fresh-var-registries
    (signals error (cl-cc/runtime/dynamic-binding:rt-symbol-value 'no-such-runtime-var))))

(it-sequential
  "rt-dynamic-bind shadows the global value; rt-dynamic-unbind restores it."
  (with-fresh-var-registries
    (cl-cc/runtime/dynamic-binding:rt-set-symbol-value 'beta 1)
    (rt-dynamic-bind 'beta 2)
    (expect (cl-cc/runtime/dynamic-binding:rt-symbol-value 'beta) :to-equal 2)
    (rt-dynamic-unbind)
    (expect (cl-cc/runtime/dynamic-binding:rt-symbol-value 'beta) :to-equal 1)))

(it-sequential
  "rt-with-dynamic-binding installs and removes the binding around its body."
  (with-fresh-var-registries
    (cl-cc/runtime/dynamic-binding:rt-set-symbol-value 'gamma 10)
    (cl-cc/runtime/dynamic-binding:rt-with-dynamic-binding
      ('gamma 20)
      (expect (cl-cc/runtime/dynamic-binding:rt-symbol-value 'gamma) :to-equal 20))
    (expect (cl-cc/runtime/dynamic-binding:rt-symbol-value 'gamma) :to-equal 10)))

(it-sequential
  "rt-register-special-variable tracks global-only status until first bind."
  (with-fresh-var-registries
    (rt-register-special-variable 'delta :global-only-p t)
    (expect (cl-cc/runtime/dynamic-binding:rt-special-variable-global-only-p 'delta) :to-be-truthy)
    (rt-dynamic-bind 'delta 5)
    (expect (cl-cc/runtime/dynamic-binding:rt-special-variable-global-only-p 'delta) :to-be-falsy)))

(in-package :cl-cc/runtime/dynamic-binding/test)

(it-sequential
  "rt-make-symbol returns a fresh uninterned symbol with the given name."
  (let ((s (cl-cc/runtime/dynamic-binding:rt-make-symbol "FOO")))
    (expect (symbolp s) :to-be-truthy)
    (expect (symbol-package s) :to-be-null)
    (expect (symbol-name s) :to-equal "FOO")))
