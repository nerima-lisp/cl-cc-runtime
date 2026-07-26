;;;; t/runtime-ops-test.lisp — Coverage for src/runtime-ops.lisp
;;;;
;;;; Fills gaps in array/vector, bitwise, logical, and math rt-* wrappers not
;;;; already exercised by runtime-test.lisp / runtime-data-ops-test.lisp.

(in-package :cl-cc-runtime/test)

(in-suite cl-cc-unit-suite)

;;; ------------------------------------------------------------
;;; Arrays / Vectors
;;; ------------------------------------------------------------

(deftest runtime-ops-make-array-fill-pointer-adjustable
  "rt-make-array honours initial-element, fill-pointer, and adjustable."
  (let ((a (cl-cc/runtime:rt-make-array 5 :initial-element 7
                                          :fill-pointer 2 :adjustable t)))
    (assert-= 7 (cl-cc/runtime:rt-aref a 0))
    (assert-= 2 (cl-cc/runtime:rt-fill-pointer a))
    (assert-= 1 (cl-cc/runtime:rt-array-has-fill-pointer-p a))
    (assert-= 1 (cl-cc/runtime:rt-array-adjustable-p a))))

(deftest runtime-ops-array-shape-accessors
  "rt-array-rank/dimension/dimensions/total-size report multidimensional shape."
  (let ((a (cl-cc/runtime:rt-make-array '(2 3) :initial-element 0)))
    (assert-= 2 (cl-cc/runtime:rt-array-rank a))
    (assert-= 2 (cl-cc/runtime:rt-array-dimension a 0))
    (assert-= 3 (cl-cc/runtime:rt-array-dimension a 1))
    (assert-equal '(2 3) (cl-cc/runtime:rt-array-dimensions a))
    (assert-= 6 (cl-cc/runtime:rt-array-total-size a))))

(deftest runtime-ops-row-major-access
  "rt-row-major-aref and rt-array-row-major-index address flattened storage."
  (let ((a (cl-cc/runtime:rt-make-array '(2 2))))
    (cl-cc/runtime:rt-aset a 1 1 99)
    (assert-= 3 (cl-cc/runtime:rt-array-row-major-index a 1 1))
    (assert-= 99 (cl-cc/runtime:rt-row-major-aref a 3))))

(deftest runtime-ops-vector-push-pop
  "rt-vector-push / push-extend / pop mutate the fill pointer as expected."
  (let ((v (cl-cc/runtime:rt-make-array 3 :fill-pointer 0)))
    (assert-= 0 (cl-cc/runtime:rt-vector-push 10 v))
    (cl-cc/runtime:rt-vector-push-extend 20 v)
    (assert-= 2 (cl-cc/runtime:rt-fill-pointer v))
    (assert-= 20 (cl-cc/runtime:rt-vector-pop v))
    (assert-= 1 (cl-cc/runtime:rt-fill-pointer v))
    (cl-cc/runtime:rt-set-fill-pointer v 0)
    (assert-= 0 (cl-cc/runtime:rt-fill-pointer v))))

(deftest runtime-ops-adjust-array-grows
  "rt-adjust-array resizes an adjustable array preserving contents."
  (let ((a (cl-cc/runtime:rt-make-array 2 :adjustable t :initial-element 1)))
    (cl-cc/runtime:rt-adjust-array a 4 :initial-element 9)
    (assert-= 4 (cl-cc/runtime:rt-array-total-size a))
    (assert-= 1 (cl-cc/runtime:rt-aref a 0))
    (assert-= 9 (cl-cc/runtime:rt-aref a 3))))

(deftest runtime-ops-array-displacement
  "rt-array-displacement reports the displaced-to array and offset."
  (let* ((base (cl-cc/runtime:rt-make-array 4 :initial-element 5))
         (disp (make-array 2 :displaced-to base :displaced-index-offset 1)))
    (multiple-value-bind (to offset) (cl-cc/runtime:rt-array-displacement disp)
      (assert-eq base to)
      (assert-= 1 offset))))

(deftest runtime-ops-plain-array-has-no-fill-pointer
  "rt-array-has-fill-pointer-p / rt-array-adjustable-p return 0 for simple arrays."
  (let ((a (cl-cc/runtime:rt-make-array 3)))
    (assert-= 0 (cl-cc/runtime:rt-array-has-fill-pointer-p a))
    (assert-= 0 (cl-cc/runtime:rt-array-adjustable-p a))))

;;; ------------------------------------------------------------
;;; Bit arrays
;;; ------------------------------------------------------------

(deftest runtime-ops-bit-vector-ops
  "rt-bit-and/or/xor/not compute elementwise bit operations."
  (let ((a #*1100)
        (b #*1010))
    (assert-equal #*1000 (cl-cc/runtime:rt-bit-and a b))
    (assert-equal #*1110 (cl-cc/runtime:rt-bit-or a b))
    (assert-equal #*0110 (cl-cc/runtime:rt-bit-xor a b))
    (assert-equal #*0011 (cl-cc/runtime:rt-bit-not a))))

(deftest runtime-ops-bit-access-set-sbit
  "rt-bit-access, rt-bit-set, and rt-sbit read/write individual bits."
  (let ((bv (make-array 4 :element-type 'bit :initial-element 0)))
    (cl-cc/runtime:rt-bit-set bv 1 1)
    (assert-= 1 (cl-cc/runtime:rt-bit-access bv 1))
    (assert-= 0 (cl-cc/runtime:rt-bit-access bv 0))
    (assert-= 1 (cl-cc/runtime:rt-sbit bv 1))))

;;; ------------------------------------------------------------
;;; Logical wrappers
;;; ------------------------------------------------------------

(deftest runtime-ops-cl-and-or
  "rt-cl-and / rt-cl-or implement short-circuit AND/OR semantics."
  (assert-= 2 (cl-cc/runtime:rt-cl-and 1 2))
  (assert-null (cl-cc/runtime:rt-cl-and nil 2))
  (assert-= 1 (cl-cc/runtime:rt-cl-or 1 2))
  (assert-= 2 (cl-cc/runtime:rt-cl-or nil 2)))

;;; ------------------------------------------------------------
;;; Bitwise
;;; ------------------------------------------------------------

(deftest runtime-ops-bitwise-integer
  "Bitwise wrappers match the CL integer operators."
  (assert-= 8 (cl-cc/runtime:rt-ash 1 3))
  (assert-= 1 (cl-cc/runtime:rt-ash 8 -3))
  (assert-= #b1000 (cl-cc/runtime:rt-logand #b1100 #b1010))
  (assert-= #b1110 (cl-cc/runtime:rt-logior #b1100 #b1010))
  (assert-= #b0110 (cl-cc/runtime:rt-logxor #b1100 #b1010))
  (assert-= -1 (cl-cc/runtime:rt-logeqv 0 0))
  (assert-= -1 (cl-cc/runtime:rt-lognot 0)))

(deftest runtime-ops-logtest-logbitp-return-flags
  "rt-logtest and rt-logbitp return 1/0 rather than boolean."
  (assert-= 1 (cl-cc/runtime:rt-logtest #b110 #b010))
  (assert-= 0 (cl-cc/runtime:rt-logtest #b100 #b010))
  (assert-= 1 (cl-cc/runtime:rt-logbitp 2 #b100))
  (assert-= 0 (cl-cc/runtime:rt-logbitp 1 #b100)))

(deftest runtime-ops-logcount-integer-length
  "rt-logcount / rt-integer-length report bit population and width."
  (assert-= 3 (cl-cc/runtime:rt-logcount #b1011))
  (assert-= 4 (cl-cc/runtime:rt-integer-length #b1011)))

;;; ------------------------------------------------------------
;;; Comparisons returning 1/0
;;; ------------------------------------------------------------

(deftest runtime-ops-equal-fn-flag
  "rt-equal-fn returns 1 for structurally equal args, 0 otherwise."
  (assert-= 1 (cl-cc/runtime:rt-equal-fn "ab" "ab"))
  (assert-= 0 (cl-cc/runtime:rt-equal-fn "ab" "ac")))

;;; ------------------------------------------------------------
;;; Math
;;; ------------------------------------------------------------

(deftest runtime-ops-math-elementary
  "Elementary math wrappers delegate to their CL counterparts."
  ;; assert-= compares with EQUAL, which does not unify 1 and 1.0, so numeric
  ;; float results are checked with = explicitly.
  (assert-= 8 (cl-cc/runtime:rt-expt 2 3))
  (assert-true (= 3.0 (cl-cc/runtime:rt-sqrt 9.0)))
  (assert-true (= 1 (cl-cc/runtime:rt-cos 0)))
  (assert-true (= 0 (cl-cc/runtime:rt-sin 0)))
  (assert-true (= 0 (cl-cc/runtime:rt-tan 0)))
  (assert-true (= 0 (cl-cc/runtime:rt-asin 0)))
  (assert-true (= 0 (cl-cc/runtime:rt-atan 0)))
  (assert-true (= 0 (cl-cc/runtime:rt-atan2 0 1)))
  (assert-true (= 0 (cl-cc/runtime:rt-sinh 0)))
  (assert-true (= 1 (cl-cc/runtime:rt-cosh 0)))
  (assert-true (= 0 (cl-cc/runtime:rt-tanh 0))))

(deftest runtime-ops-math-acos-exp
  "rt-acos and rt-exp evaluate correctly at reference points."
  (assert-true (= 0 (cl-cc/runtime:rt-acos 1)))
  (assert-true (= 1 (cl-cc/runtime:rt-exp 0))))

(deftest runtime-ops-math-rounding-integer
  "Integer rounding wrappers return the primary integer value."
  (assert-= 3 (cl-cc/runtime:rt-floor 7/2))
  (assert-= 4 (cl-cc/runtime:rt-ceiling 7/2))
  (assert-= 3 (cl-cc/runtime:rt-truncate 7/2))
  (assert-= 4 (cl-cc/runtime:rt-round 7/2)))

(deftest runtime-ops-math-rounding-float
  "Float rounding wrappers return float results."
  (assert-= 3.0 (cl-cc/runtime:rt-ffloor 3.7))
  (assert-= 4.0 (cl-cc/runtime:rt-fceiling 3.2))
  (assert-= 3.0 (cl-cc/runtime:rt-ftruncate 3.7))
  (assert-= 4.0 (cl-cc/runtime:rt-fround 3.7)))

(deftest runtime-ops-float-introspection
  "Float-part wrappers expose IEEE decomposition data."
  (assert-true (= 2 (cl-cc/runtime:rt-float 2)))
  (assert-true (plusp (cl-cc/runtime:rt-float-precision 1.0d0)))
  (assert-= 2 (cl-cc/runtime:rt-float-radix 1.0d0))
  (assert-true (= 1.0d0 (cl-cc/runtime:rt-float-sign 3.0d0)))
  (assert-true (= -1.0d0 (cl-cc/runtime:rt-float-sign -3.0d0)))
  (assert-true (plusp (cl-cc/runtime:rt-float-digits 1.0d0))))

(deftest runtime-ops-decode-float-roundtrip
  "rt-decode-float / rt-scale-float reconstruct the original magnitude."
  (multiple-value-bind (significand exponent sign)
      (cl-cc/runtime:rt-decode-float 8.0d0)
    (assert-= 1.0d0 sign)
    (assert-= 8.0d0 (* sign (cl-cc/runtime:rt-scale-float significand exponent)))))

(deftest runtime-ops-integer-decode-float
  "rt-integer-decode-float returns integer significand/exponent/sign."
  (multiple-value-bind (significand exponent sign)
      (cl-cc/runtime:rt-integer-decode-float 1.0d0)
    (assert-true (integerp significand))
    (assert-true (integerp exponent))
    (assert-= 1 sign)))

(deftest runtime-ops-rational-conversions
  "rt-rational / rt-rationalize / rt-numerator / rt-denominator on ratios."
  (assert-= 1/2 (cl-cc/runtime:rt-rational 0.5d0))
  (assert-= 1/2 (cl-cc/runtime:rt-rationalize 0.5d0))
  (assert-= 3 (cl-cc/runtime:rt-numerator 3/4))
  (assert-= 4 (cl-cc/runtime:rt-denominator 3/4)))

(deftest runtime-ops-complex-arithmetic
  "Complex constructors and part accessors round-trip."
  (let ((z (cl-cc/runtime:rt-complex 3 4)))
    (assert-= 3 (cl-cc/runtime:rt-realpart z))
    (assert-= 4 (cl-cc/runtime:rt-imagpart z))
    (assert-= #C(3 -4) (cl-cc/runtime:rt-conjugate z))
    (assert-true (= 0 (cl-cc/runtime:rt-phase 5)))))

(deftest runtime-ops-gcd-lcm
  "rt-gcd / rt-lcm compute divisor and multiple."
  (assert-= 6 (cl-cc/runtime:rt-gcd 12 18))
  (assert-= 36 (cl-cc/runtime:rt-lcm 12 18)))
