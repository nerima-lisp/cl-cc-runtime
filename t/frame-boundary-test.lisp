;;;; t/frame-boundary-test.lisp — additional vm-frame / frame-pool coverage (src/frame.lisp).
;;;; Complements t/frame-test.lisp: pool exhaustion/overflow, raw constructor
;;;; defaults, boundary register access, and reset of the closure/return-frame fields.
(in-package :cl-cc-runtime/test)

(describe
  "vm-frame construction (frame.lisp)"
  (it
    "a raw frame has 256 registers, all +val-nil+, and nil meta-fields"
    (let ((f (cl-cc/runtime::%make-vm-frame)))
      (expect (length (cl-cc/runtime::vm-frame-registers f)) :to-be 256)
      (expect (cl-cc/runtime::vm-frame-closure f) :to-be-null)
      (expect (cl-cc/runtime::vm-frame-return-frame f) :to-be-null)
      (expect (cl-cc/runtime::vm-frame-sp f) :to-be 0)
      (expect (cl-cc/runtime::vm-frame-pc f) :to-be 0)
      (expect
        (every
          (lambda (x)
            (= x cl-cc/runtime:+val-nil+))
          (cl-cc/runtime::vm-frame-registers f))
        :to-be-truthy)))
  (it
    "the register array is a specialized (unsigned-byte 64) simple array"
    (let ((f (cl-cc/runtime::%make-vm-frame)))
      (expect
        (typep
          (cl-cc/runtime::vm-frame-registers f)
          '(simple-array (unsigned-byte 64) (*)))
        :to-be-truthy)))
  (it
    "+frame-pool-size+ is 1024"
    (expect cl-cc/runtime::+frame-pool-size+ :to-be 1024)))

(describe
  "frame-pool exhaustion and overflow (frame.lisp)"
  (it
    "initialize-frame-pool stocks the pool to full"
    (cl-cc/runtime::initialize-frame-pool)
    (expect cl-cc/runtime::*frame-pool-top* :to-be cl-cc/runtime::+frame-pool-size+))
  (it
    "acquire on an exhausted pool allocates a fresh frame and leaves top at zero"
    (cl-cc/runtime::initialize-frame-pool)
    (setf cl-cc/runtime::*frame-pool-top* 0)
    (let ((f (cl-cc/runtime::frame-pool-acquire)))
      (expect (cl-cc/runtime::vm-frame-p f) :to-be-truthy)
      (expect cl-cc/runtime::*frame-pool-top* :to-be 0))
    (cl-cc/runtime::initialize-frame-pool))
  (it
    "release on a full pool drops the frame, leaving top unchanged"
    (cl-cc/runtime::initialize-frame-pool)
    (let ((top-before cl-cc/runtime::*frame-pool-top*))
      (cl-cc/runtime::frame-pool-release (cl-cc/runtime::%make-vm-frame))
      (expect cl-cc/runtime::*frame-pool-top* :to-be top-before)))
  (it
    "acquire decrements the pool top by one"
    (cl-cc/runtime::initialize-frame-pool)
    (let ((before cl-cc/runtime::*frame-pool-top*))
      (cl-cc/runtime::frame-pool-acquire)
      (expect cl-cc/runtime::*frame-pool-top* :to-be (1- before)))
    (cl-cc/runtime::initialize-frame-pool)))

(describe
  "register access boundaries (frame.lisp)"
  (it
    "registers 0 and 255 round-trip full 64-bit values"
    (let ((f (cl-cc/runtime::%make-vm-frame))
          (big (1- (ash 1 64))))
      (cl-cc/runtime::frame-reg-set f 0 big)
      (cl-cc/runtime::frame-reg-set f 255 1)
      (expect (cl-cc/runtime::frame-reg-get f 0) :to-be big)
      (expect (cl-cc/runtime::frame-reg-get f 255) :to-be 1)))
  (it-property
    "any register index stores and returns its value independently"
    ((idx (gen-integer :min 0 :max 255))
      (val (gen-integer :min 0 :max #xffffffffffffffff)))
    (let ((f (cl-cc/runtime::%make-vm-frame)))
      (expect (cl-cc/runtime::frame-reg-set f idx val) :to-be val)
      (expect (cl-cc/runtime::frame-reg-get f idx) :to-be val))))

(describe
  "frame-reset clears object references (frame.lisp)"
  (it
    "reset nils out closure and return-frame"
    (let ((f (cl-cc/runtime::%make-vm-frame))
          (caller (cl-cc/runtime::%make-vm-frame)))
      (setf (cl-cc/runtime::vm-frame-closure f) :some-closure
            (cl-cc/runtime::vm-frame-return-frame f) caller)
      (cl-cc/runtime::frame-reset f)
      (expect (cl-cc/runtime::vm-frame-closure f) :to-be-null)
      (expect (cl-cc/runtime::vm-frame-return-frame f) :to-be-null)))
  (it
    "a released frame's object references are cleared on the next acquire"
    (cl-cc/runtime::initialize-frame-pool)
    (let ((f (cl-cc/runtime::frame-pool-acquire)))
      (setf (cl-cc/runtime::vm-frame-closure f) :leak)
      (cl-cc/runtime::frame-pool-release f)
      (let ((f2 (cl-cc/runtime::frame-pool-acquire)))
        (expect (cl-cc/runtime::vm-frame-closure f2) :to-be-null)))
    (cl-cc/runtime::initialize-frame-pool)))
