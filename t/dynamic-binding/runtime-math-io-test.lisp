(in-package :cl-cc/runtime/dynamic-binding/test)

(defmacro with-fresh-var-registries (&body body)
  `(let ((cl-cc/runtime::*rt-global-var-registry* (make-hash-table :test #'eq))
        (cl-cc/runtime::*rt-special-variable-metadata* (make-hash-table :test #'eq))
        (cl-cc/runtime::*rt-dynamic-binding-stacks* (make-hash-table :test #'equal)))
    ,@body))

(it-sequential
  "rt-set-symbol-value / rt-symbol-value use the runtime global registry."
  (with-fresh-var-registries
    (cl-cc/runtime::rt-set-symbol-value 'alpha 11)
    (expect (cl-cc/runtime::rt-symbol-value 'alpha) :to-equal 11)
    (expect (cl-cc/runtime::rt-boundp 'alpha) :to-equal 1)
    (cl-cc/runtime::rt-makunbound 'alpha)
    (expect (cl-cc/runtime::rt-boundp 'alpha) :to-equal 0)))

(it-sequential
  "rt-symbol-value signals when the variable was never assigned."
  (with-fresh-var-registries
    (signals error (cl-cc/runtime::rt-symbol-value 'no-such-runtime-var))))

(it-sequential
  "rt-dynamic-bind shadows the global value; rt-dynamic-unbind restores it."
  (with-fresh-var-registries
    (cl-cc/runtime::rt-set-symbol-value 'beta 1)
    (cl-cc/runtime::rt-dynamic-bind 'beta 2)
    (expect (cl-cc/runtime::rt-symbol-value 'beta) :to-equal 2)
    (cl-cc/runtime::rt-dynamic-unbind)
    (expect (cl-cc/runtime::rt-symbol-value 'beta) :to-equal 1)))

(it-sequential
  "rt-with-dynamic-binding installs and removes the binding around its body."
  (with-fresh-var-registries
    (cl-cc/runtime::rt-set-symbol-value 'gamma 10)
    (cl-cc/runtime::rt-with-dynamic-binding
      ('gamma 20)
      (expect (cl-cc/runtime::rt-symbol-value 'gamma) :to-equal 20))
    (expect (cl-cc/runtime::rt-symbol-value 'gamma) :to-equal 10)))

(it-sequential
  "rt-register-special-variable tracks global-only status until first bind."
  (with-fresh-var-registries
    (cl-cc/runtime::rt-register-special-variable 'delta :global-only-p t)
    (expect (cl-cc/runtime::rt-special-variable-global-only-p 'delta) :to-be-truthy)
    (cl-cc/runtime::rt-dynamic-bind 'delta 5)
    (expect (cl-cc/runtime::rt-special-variable-global-only-p 'delta) :to-be-falsy)))
