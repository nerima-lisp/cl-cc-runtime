;;;; t/frame-test.lisp - vm-frame and Frame Pool Tests
;;;
;;; Tests for the fixed-size register array, frame pool acquire/release,
;;; register read/write, and frame-reset.
(in-package :cl-cc-runtime/test)

;;; ------------------------------------------------------------
;;; Suite
;;; ------------------------------------------------------------
;;; ------------------------------------------------------------
;;; Frame construction
;;; ------------------------------------------------------------
(it-sequential
  "frame-pool-acquire returns a vm-frame-p object."
  (cl-cc/runtime::initialize-frame-pool)
  (let ((f (cl-cc/runtime::frame-pool-acquire)))
    (expect (cl-cc/runtime::vm-frame-p f) :to-be-truthy)))

(it-sequential
  "All 256 registers of a freshly acquired frame are initialized to +val-nil+."
  (cl-cc/runtime::initialize-frame-pool)
  (let ((f (cl-cc/runtime::frame-pool-acquire)))
    (dotimes (i 256)
      (expect (cl-cc/runtime::frame-reg-get f i) :to-equal cl-cc/runtime:+val-nil+))))

(it-sequential
  "A freshly acquired frame has sp=0 and pc=0."
  (cl-cc/runtime::initialize-frame-pool)
  (let ((f (cl-cc/runtime::frame-pool-acquire)))
    (expect (cl-cc/runtime::vm-frame-sp f) :to-equal 0)
    (expect (cl-cc/runtime::vm-frame-pc f) :to-equal 0)))

;;; ------------------------------------------------------------
;;; Register read/write
;;; ------------------------------------------------------------
(it-sequential
  "frame-reg-set stores a value; frame-reg-get retrieves it."
  (cl-cc/runtime::initialize-frame-pool)
  (let ((f (cl-cc/runtime::frame-pool-acquire)))
    (cl-cc/runtime::frame-reg-set f 0 (cl-cc/runtime::encode-fixnum 42))
    (expect
      (cl-cc/runtime::decode-fixnum (cl-cc/runtime::frame-reg-get f 0))
      :to-equal
      42)))

(it-sequential
  "All 256 registers can be written and read independently."
  (cl-cc/runtime::initialize-frame-pool)
  (let ((f (cl-cc/runtime::frame-pool-acquire)))
    (dotimes (i 256)
      (cl-cc/runtime::frame-reg-set f i (cl-cc/runtime::encode-fixnum i)))
    (dotimes (i 256)
      (expect
        (cl-cc/runtime::decode-fixnum (cl-cc/runtime::frame-reg-get f i))
        :to-equal
        i))))

(it-sequential
  "frame-reg-set returns the value it stored."
  (cl-cc/runtime::initialize-frame-pool)
  (let* ((f (cl-cc/runtime::frame-pool-acquire))
         (val (cl-cc/runtime::encode-fixnum 7))
         (ret (cl-cc/runtime::frame-reg-set f 3 val)))
    (expect ret :to-equal val)))

(it-sequential
  "Writing the same register twice stores the second value."
  (cl-cc/runtime::initialize-frame-pool)
  (let ((f (cl-cc/runtime::frame-pool-acquire)))
    (cl-cc/runtime::frame-reg-set f 5 (cl-cc/runtime::encode-fixnum 100))
    (cl-cc/runtime::frame-reg-set f 5 (cl-cc/runtime::encode-fixnum 200))
    (expect
      (cl-cc/runtime::decode-fixnum (cl-cc/runtime::frame-reg-get f 5))
      :to-equal
      200)))

(it-sequential
  "An unwritten register returns +val-nil+."
  (cl-cc/runtime::initialize-frame-pool)
  (let ((f (cl-cc/runtime::frame-pool-acquire)))
    (expect (cl-cc/runtime::frame-reg-get f 255) :to-equal cl-cc/runtime:+val-nil+)))

;;; ------------------------------------------------------------
;;; frame-reset
;;; ------------------------------------------------------------
(it-sequential "frame-reset: clears all registers to +val-nil+; zeroes pc/sp; returns frame." (cl-cc/runtime::initialize-frame-pool)
  (let ((f (cl-cc/runtime::frame-pool-acquire)))
    ;; fill registers, then reset
    (dotimes (i 256)
      (cl-cc/runtime::frame-reg-set f i (cl-cc/runtime::encode-fixnum i)))
    (setf (cl-cc/runtime::vm-frame-pc f) 99
          (cl-cc/runtime::vm-frame-sp f) 42)
    (let ((ret (cl-cc/runtime::frame-reset f)))
      ;; returns the frame
      (expect ret :to-equal f)
      ;; all registers cleared
      (dotimes (i 256)
        (expect (cl-cc/runtime::frame-reg-get f i) :to-equal cl-cc/runtime:+val-nil+))
      ;; pc and sp zeroed
      (expect (cl-cc/runtime::vm-frame-pc f) :to-equal 0)
      (expect (cl-cc/runtime::vm-frame-sp f) :to-equal 0))))

;;; ------------------------------------------------------------
;;; frame-pool-release
;;; ------------------------------------------------------------
(it-sequential "A released-then-acquired frame has all registers as +val-nil+ and pc/sp zeroed." (cl-cc/runtime::initialize-frame-pool)
  (let ((f (cl-cc/runtime::frame-pool-acquire)))
    (cl-cc/runtime::frame-reg-set f 10 (cl-cc/runtime::encode-fixnum 999))
    (cl-cc/runtime::frame-pool-release f)
    ;; Acquire a frame; it may be the same one just released.
    (let ((f2 (cl-cc/runtime::frame-pool-acquire)))
      (expect (cl-cc/runtime::frame-reg-get f2 10) :to-equal cl-cc/runtime:+val-nil+)))
  (cl-cc/runtime::initialize-frame-pool)
  (let ((f (cl-cc/runtime::frame-pool-acquire)))
    (setf (cl-cc/runtime::vm-frame-pc f) 5
          (cl-cc/runtime::vm-frame-sp f) 3)
    (cl-cc/runtime::frame-pool-release f)
    (let ((f2 (cl-cc/runtime::frame-pool-acquire)))
      (expect (cl-cc/runtime::vm-frame-pc f2) :to-equal 0)
      (expect (cl-cc/runtime::vm-frame-sp f2) :to-equal 0))))

;;; ------------------------------------------------------------
;;; Frame register count constant
;;; ------------------------------------------------------------
(it-sequential
  "+frame-register-count+ is 256."
  (expect cl-cc/runtime:+frame-register-count+ :to-equal 256))

(it-sequential
  "The arg range [+frame-arg-start+, +frame-arg-end+] is entirely within caller-save."
  (expect
    (<=
      cl-cc/runtime:+frame-arg-start+
      cl-cc/runtime:+frame-arg-end+
      cl-cc/runtime:+frame-caller-save-end+)
    :to-be-truthy))

(it-sequential
  "+frame-spill-start+ is above +frame-callee-save-end+."
  (expect
    (> cl-cc/runtime:+frame-spill-start+ cl-cc/runtime:+frame-callee-save-end+)
    :to-be-truthy))
