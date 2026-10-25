(in-package :cl-cc/runtime/dynamic-binding/test)

(it-sequential "rt-make-symbol-creates-uninterned"
  (let ((s (cl-cc/runtime/dynamic-binding:rt-make-symbol "TEST")))
    (expect (symbol-name s) :to-equal "TEST")
    (expect (symbol-package s) :to-be-falsy)))

(it-sequential "rt-boundp-and-makunbound"
  (let ((sym (gensym "RT-BOUND-TEST-")))
    (expect (= 0 (cl-cc/runtime/dynamic-binding:rt-boundp sym)) :to-be-truthy)
    (cl-cc/runtime/dynamic-binding:rt-set-symbol-value sym 42)
    (expect (= 1 (cl-cc/runtime/dynamic-binding:rt-boundp sym)) :to-be-truthy)
    (cl-cc/runtime/dynamic-binding:rt-makunbound sym)
    (expect (= 0 (cl-cc/runtime/dynamic-binding:rt-boundp sym)) :to-be-truthy)))
