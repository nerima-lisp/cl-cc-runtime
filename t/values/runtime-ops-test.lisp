;;;; t/runtime-ops-test.lisp — Coverage for src/runtime-ops.lisp
;;;;
;;;; Fills gaps in array/vector, bitwise, logical, and math rt-* wrappers not
;;;; already exercised by runtime-test.lisp / runtime-data-ops-test.lisp.
(in-package :cl-cc/runtime/values/test)

;;; ------------------------------------------------------------
;;; Arrays / Vectors
;;; ------------------------------------------------------------
(it-sequential
  "rt-make-array honours initial-element, fill-pointer, and adjustable."
  (let ((a
        (cl-cc/runtime/values:rt-make-array 5 :initial-element 7 :fill-pointer 2 :adjustable t)))
    (expect (cl-cc/runtime/values:rt-aref a 0) :to-equal 7)
    (expect (cl-cc/runtime/values:rt-fill-pointer a) :to-equal 2)
    (expect (cl-cc/runtime/values:rt-array-has-fill-pointer-p a) :to-equal 1)
    (expect (cl-cc/runtime/values:rt-array-adjustable-p a) :to-equal 1)))

(it-sequential
  "rt-array-rank/dimension/dimensions/total-size report multidimensional shape."
  (let ((a (cl-cc/runtime/values:rt-make-array '(2 3) :initial-element 0)))
    (expect (cl-cc/runtime/values:rt-array-rank a) :to-equal 2)
    (expect (cl-cc/runtime/values:rt-array-dimension a 0) :to-equal 2)
    (expect (cl-cc/runtime/values:rt-array-dimension a 1) :to-equal 3)
    (expect (cl-cc/runtime/values:rt-array-dimensions a) :to-equal '(2 3))
    (expect (cl-cc/runtime/values:rt-array-total-size a) :to-equal 6)))

(it-sequential
  "rt-row-major-aref and rt-array-row-major-index address flattened storage."
  (let ((a (cl-cc/runtime/values:rt-make-array '(2 2))))
    (cl-cc/runtime/values:rt-aset a 1 1 99)
    (expect (cl-cc/runtime/values:rt-array-row-major-index a 1 1) :to-equal 3)
    (expect (cl-cc/runtime/values:rt-row-major-aref a 3) :to-equal 99)))

(it-sequential
  "rt-vector-push / push-extend / pop mutate the fill pointer as expected."
  (let ((v (cl-cc/runtime/values:rt-make-array 3 :fill-pointer 0)))
    (expect (cl-cc/runtime/values:rt-vector-push 10 v) :to-equal 0)
    (cl-cc/runtime/values:rt-vector-push-extend 20 v)
    (expect (cl-cc/runtime/values:rt-fill-pointer v) :to-equal 2)
    (expect (cl-cc/runtime/values:rt-vector-pop v) :to-equal 20)
    (expect (cl-cc/runtime/values:rt-fill-pointer v) :to-equal 1)
    (cl-cc/runtime/values:rt-set-fill-pointer v 0)
    (expect (cl-cc/runtime/values:rt-fill-pointer v) :to-equal 0)))

(it-sequential
  "rt-adjust-array resizes an adjustable array preserving contents."
  (let ((a (cl-cc/runtime/values:rt-make-array 2 :adjustable t :initial-element 1)))
    (cl-cc/runtime/values:rt-adjust-array a 4 :initial-element 9)
    (expect (cl-cc/runtime/values:rt-array-total-size a) :to-equal 4)
    (expect (cl-cc/runtime/values:rt-aref a 0) :to-equal 1)
    (expect (cl-cc/runtime/values:rt-aref a 3) :to-equal 9)))

(it-sequential
  "rt-array-displacement reports the displaced-to array and offset."
  (let* ((base (cl-cc/runtime/values:rt-make-array 4 :initial-element 5))
         (disp (make-array 2 :displaced-to base :displaced-index-offset 1)))
    (multiple-value-bind (to offset) (cl-cc/runtime/values:rt-array-displacement disp)
      (expect to :to-be base)
      (expect offset :to-equal 1))))

(it-sequential
  "rt-make-array accepts displaced-to and preserves writes through the base."
  (let* ((base (cl-cc/runtime/values:rt-make-array 4 :initial-element 0))
         (disp (cl-cc/runtime/values:rt-make-array 2 :displaced-to base
                                             :displaced-index-offset 1)))
    (cl-cc/runtime/values:rt-aset disp 0 42)
    (expect (cl-cc/runtime/values:rt-aref base 1) :to-equal 42)
    (multiple-value-bind (to offset) (cl-cc/runtime/values:rt-array-displacement disp)
      (expect to :to-be base)
      (expect offset :to-equal 1))))

(it-sequential
  "rt-array-has-fill-pointer-p / rt-array-adjustable-p return 0 for simple arrays."
  (let ((a (cl-cc/runtime/values:rt-make-array 3)))
    (expect (cl-cc/runtime/values:rt-array-has-fill-pointer-p a) :to-equal 0)
    (expect (cl-cc/runtime/values:rt-array-adjustable-p a) :to-equal 0)))

;;; ------------------------------------------------------------
;;; Bit arrays
;;; ------------------------------------------------------------
(it-sequential
  "rt-bit-and/or/xor/not compute elementwise bit operations."
  (let ((a #*1100)
        (b #*1010))
    (expect (cl-cc/runtime/values:rt-bit-and a b) :to-equal #*1000)
    (expect (cl-cc/runtime/values:rt-bit-or a b) :to-equal #*1110)
    (expect (cl-cc/runtime/values:rt-bit-xor a b) :to-equal #*0110)
    (expect (cl-cc/runtime/values:rt-bit-not a) :to-equal #*0011)))

(it-sequential
  "rt-bit-access, rt-bit-set, and rt-sbit read/write individual bits."
  (let ((bv (make-array 4 :element-type 'bit :initial-element 0)))
    (cl-cc/runtime/values:rt-bit-set bv 1 1)
    (expect (cl-cc/runtime/values:rt-bit-access bv 1) :to-equal 1)
    (expect (cl-cc/runtime/values:rt-bit-access bv 0) :to-equal 0)
    (expect (cl-cc/runtime/values:rt-sbit bv 1) :to-equal 1)))

;;; ------------------------------------------------------------
;;; Logical wrappers
;;; ------------------------------------------------------------
(it-sequential
  "rt-cl-and / rt-cl-or implement short-circuit AND/OR semantics."
  (expect (cl-cc/runtime/values:rt-cl-and 1 2) :to-equal 2)
  (expect (cl-cc/runtime/values:rt-cl-and nil 2) :to-be-null)
  (expect (cl-cc/runtime/values:rt-cl-or 1 2) :to-equal 1)
  (expect (cl-cc/runtime/values:rt-cl-or nil 2) :to-equal 2))

;;; ------------------------------------------------------------
;;; Bitwise
;;; ------------------------------------------------------------
(it-sequential
  "Bitwise wrappers match the CL integer operators."
  (expect (cl-cc/runtime/values:rt-ash 1 3) :to-equal 8)
  (expect (cl-cc/runtime/values:rt-ash 8 -3) :to-equal 1)
  (expect (cl-cc/runtime/values:rt-logand #b1100 #b1010) :to-equal #b1000)
  (expect (cl-cc/runtime/values:rt-logior #b1100 #b1010) :to-equal #b1110)
  (expect (cl-cc/runtime/values:rt-logxor #b1100 #b1010) :to-equal #b0110)
  (expect (cl-cc/runtime/values:rt-logeqv 0 0) :to-equal -1)
  (expect (cl-cc/runtime/values:rt-lognot 0) :to-equal -1))

(it-sequential
  "rt-logtest and rt-logbitp return 1/0 rather than boolean."
  (expect (cl-cc/runtime/values:rt-logtest #b110 #b010) :to-equal 1)
  (expect (cl-cc/runtime/values:rt-logtest #b100 #b010) :to-equal 0)
  (expect (cl-cc/runtime/values:rt-logbitp 2 #b100) :to-equal 1)
  (expect (cl-cc/runtime/values:rt-logbitp 1 #b100) :to-equal 0))

(it-sequential
  "rt-logcount / rt-integer-length report bit population and width."
  (expect (cl-cc/runtime/values:rt-logcount #b1011) :to-equal 3)
  (expect (cl-cc/runtime/values:rt-integer-length #b1011) :to-equal 4))

;;; ------------------------------------------------------------
;;; Comparisons returning 1/0
;;; ------------------------------------------------------------
(it-sequential
  "rt-equal-fn returns 1 for structurally equal args, 0 otherwise."
  (expect (cl-cc/runtime/values:rt-equal-fn "ab" "ab") :to-equal 1)
  (expect (cl-cc/runtime/values:rt-equal-fn "ab" "ac") :to-equal 0))

;;; ------------------------------------------------------------
;;; Math
;;; ------------------------------------------------------------
(it-sequential "Elementary math wrappers delegate to their CL counterparts."
  ;; assert-= compares with EQUAL, which does not unify 1 and 1.0, so numeric
  ;; float results are checked with = explicitly.
  (expect (cl-cc/runtime/values:rt-expt 2 3) :to-equal 8)
  (expect (= 3.0 (cl-cc/runtime/values:rt-sqrt 9.0)) :to-be-truthy)
  (expect (= 1 (cl-cc/runtime/values:rt-cos 0)) :to-be-truthy)
  (expect (= 0 (cl-cc/runtime/values:rt-sin 0)) :to-be-truthy)
  (expect (= 0 (cl-cc/runtime/values:rt-tan 0)) :to-be-truthy)
  (expect (= 0 (cl-cc/runtime/values:rt-asin 0)) :to-be-truthy)
  (expect (= 0 (cl-cc/runtime/values:rt-atan 0)) :to-be-truthy)
  (expect (= 0 (cl-cc/runtime/values:rt-atan2 0 1)) :to-be-truthy)
  (expect (= 0 (cl-cc/runtime/values:rt-sinh 0)) :to-be-truthy)
  (expect (= 1 (cl-cc/runtime/values:rt-cosh 0)) :to-be-truthy)
  (expect (= 0 (cl-cc/runtime/values:rt-tanh 0)) :to-be-truthy))

(it-sequential
  "rt-acos and rt-exp evaluate correctly at reference points."
  (expect (= 0 (cl-cc/runtime/values:rt-acos 1)) :to-be-truthy)
  (expect (= 1 (cl-cc/runtime/values:rt-exp 0)) :to-be-truthy))

(it-sequential
  "Integer rounding wrappers return the primary integer value."
  (expect (cl-cc/runtime/values:rt-floor 7/2) :to-equal 3)
  (expect (cl-cc/runtime/values:rt-ceiling 7/2) :to-equal 4)
  (expect (cl-cc/runtime/values:rt-truncate 7/2) :to-equal 3)
  (expect (cl-cc/runtime/values:rt-round 7/2) :to-equal 4))

(it-sequential
  "Float rounding wrappers return float results."
  (expect (cl-cc/runtime/values:rt-ffloor 3.7) :to-equal 3.0)
  (expect (cl-cc/runtime/values:rt-fceiling 3.2) :to-equal 4.0)
  (expect (cl-cc/runtime/values:rt-ftruncate 3.7) :to-equal 3.0)
  (expect (cl-cc/runtime/values:rt-fround 3.7) :to-equal 4.0))

(it-sequential
  "Float-part wrappers expose IEEE decomposition data."
  (expect (= 2 (cl-cc/runtime/values:rt-float 2)) :to-be-truthy)
  (expect (plusp (cl-cc/runtime/values:rt-float-precision 1.0d0)) :to-be-truthy)
  (expect (cl-cc/runtime/values:rt-float-radix 1.0d0) :to-equal 2)
  (expect (= 1.0d0 (cl-cc/runtime/values:rt-float-sign 3.0d0)) :to-be-truthy)
  (expect (= -1.0d0 (cl-cc/runtime/values:rt-float-sign -3.0d0)) :to-be-truthy)
  (expect (plusp (cl-cc/runtime/values:rt-float-digits 1.0d0)) :to-be-truthy))

(it-sequential
  "rt-decode-float / rt-scale-float reconstruct the original magnitude."
  (multiple-value-bind (significand exponent sign) (cl-cc/runtime/values:rt-decode-float 8.0d0)
    (expect sign :to-equal 1.0d0)
    (expect
      (* sign (cl-cc/runtime/values:rt-scale-float significand exponent))
      :to-equal
      8.0d0)))

(it-sequential
  "rt-integer-decode-float returns integer significand/exponent/sign."
  (multiple-value-bind (significand exponent sign) (cl-cc/runtime/values:rt-integer-decode-float 1.0d0)
    (expect (integerp significand) :to-be-truthy)
    (expect (integerp exponent) :to-be-truthy)
    (expect sign :to-equal 1)))

(it-sequential
  "rt-rational / rt-rationalize / rt-numerator / rt-denominator on ratios."
  (expect (cl-cc/runtime/values:rt-rational 0.5d0) :to-equal 1/2)
  (expect (cl-cc/runtime/values:rt-rationalize 0.5d0) :to-equal 1/2)
  (expect (cl-cc/runtime/values:rt-numerator 3/4) :to-equal 3)
  (expect (cl-cc/runtime/values:rt-denominator 3/4) :to-equal 4))

(it-sequential
  "Complex constructors and part accessors round-trip."
  (let ((z (cl-cc/runtime/values:rt-complex 3 4)))
    (expect (cl-cc/runtime/values:rt-realpart z) :to-equal 3)
    (expect (cl-cc/runtime/values:rt-imagpart z) :to-equal 4)
    (expect (cl-cc/runtime/values:rt-conjugate z) :to-equal #C(3 -4))
    (expect (= 0 (cl-cc/runtime/values:rt-phase 5)) :to-be-truthy)))

(it-sequential
  "rt-gcd / rt-lcm compute divisor and multiple."
  (expect (cl-cc/runtime/values:rt-gcd 12 18) :to-equal 6)
  (expect (cl-cc/runtime/values:rt-lcm 12 18) :to-equal 36))
