(in-package :cl-cc/runtime/execution/test)

(describe
  "return-address poisoning (runtime-stack.lisp)"
  (it
    "poison then unpoison is the identity"
    (dolist (n '(0 1 42 #x1234 #xdeadbeef #xfffffffffffff))
      (expect
        (cl-cc/runtime::rt-unpoison-return-address
          (cl-cc/runtime::rt-poison-return-address n))
        :to-be
        n)))
  (it
    "a poisoned address is recognised as poisoned"
    (expect
      (cl-cc/runtime::rt-return-address-poisoned-p
        (cl-cc/runtime::rt-poison-return-address 0))
      :to-be-truthy))
  (it
    "a raw small address is not flagged as poisoned"
    (expect (cl-cc/runtime::rt-return-address-poisoned-p 4096) :to-be-null))
  (it
    "poisoning a non-integer signals a type error"
    (signals type-error (cl-cc/runtime::rt-poison-return-address :not-an-int)))
  (it-property
    "poison/unpoison round-trips arbitrary addresses"
    ((addr (gen-integer :min 0 :max #xffffffffffff)))
    (expect
      (cl-cc/runtime::rt-unpoison-return-address
        (cl-cc/runtime::rt-poison-return-address addr))
      :to-be
      addr)))

(describe "stack-overflow guard (runtime-stack.lisp)"
  (it "rt-check-stack-overflow returns the depth when below the limit"
    (let ((cl-cc/runtime::*max-call-stack-depth* 10))
      (expect (cl-cc/runtime::rt-check-stack-overflow 3) :to-be 3)))

  (it "rt-check-stack-overflow signals at the limit"
    (let ((cl-cc/runtime::*max-call-stack-depth* 5))
      (signals cl-cc/runtime::rt-stack-overflow (cl-cc/runtime::rt-check-stack-overflow 5))))

  (it "the signalled condition carries the offending depth and limit"
    (let ((cl-cc/runtime::*max-call-stack-depth* 7))
      (handler-case (cl-cc/runtime::rt-check-stack-overflow 7)
        (cl-cc/runtime::rt-stack-overflow (c)
          (expect (cl-cc/runtime::rt-stack-overflow-depth c) :to-be 7)
          (expect (cl-cc/runtime::rt-stack-overflow-limit c) :to-be 7)))))

  (it "rt-with-call-stack-guard increments the logical depth inside the body"
    (let ((cl-cc/runtime::*rt-call-stack-depth* 0))
      (cl-cc/runtime::rt-with-call-stack-guard ()
        (expect cl-cc/runtime::*rt-call-stack-depth* :to-be 1))
      ;; depth is restored on exit
      (expect cl-cc/runtime::*rt-call-stack-depth* :to-be 0)))

  (it "nested guards eventually trip the overflow condition"
    (let ((cl-cc/runtime::*max-call-stack-depth* 4)
          (cl-cc/runtime::*rt-call-stack-depth* 0))
      (labels ((recurse () (cl-cc/runtime::rt-with-call-stack-guard () (recurse))))
        (signals cl-cc/runtime::rt-stack-overflow (recurse))))))
