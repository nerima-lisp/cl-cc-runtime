(in-package :cl-cc/runtime/execution/test)

(describe
  "return-address poisoning (runtime-stack.lisp)"
  (it
    "poison then unpoison is the identity"
    (dolist (n '(0 1 42 #x1234 #xdeadbeef #xfffffffffffff))
      (expect
        (cl-cc/runtime/execution:rt-unpoison-return-address
          (cl-cc/runtime/execution:rt-poison-return-address n))
        :to-be
        n)))
  (it
    "a poisoned address is recognised as poisoned"
    (expect
      (cl-cc/runtime/execution:rt-return-address-poisoned-p
        (cl-cc/runtime/execution:rt-poison-return-address 0))
      :to-be-truthy))
  (it
    "a raw small address is not flagged as poisoned"
    (expect (cl-cc/runtime/execution:rt-return-address-poisoned-p 4096) :to-be-null))
  (it
    "poisoning a non-integer signals a type error"
    (signals type-error (cl-cc/runtime/execution:rt-poison-return-address :not-an-int)))
  (it-property
    "poison/unpoison round-trips arbitrary addresses"
    ((addr (gen-integer :min 0 :max #xffffffffffff)))
    (expect
      (cl-cc/runtime/execution:rt-unpoison-return-address
        (cl-cc/runtime/execution:rt-poison-return-address addr))
      :to-be
      addr)))

