;;;; t/value-test.lisp - NaN-Boxing Value Representation Tests
;;;
;;; Tests for cl-cc/runtime NaN-boxing: type predicates, encode/decode
;;; round-trips, singleton constants, and edge-case bit patterns.
(in-package :cl-cc-runtime/test)

;;; ------------------------------------------------------------
;;; Suite
;;; ------------------------------------------------------------
;;; ------------------------------------------------------------
;;; Singleton constants
;;; ------------------------------------------------------------
(it-sequential-each (("nil" cl-cc/runtime:+val-nil+ #x7FFF000000000000)
                      ("t" cl-cc/runtime:+val-t+ #x7FFF000000000001)
                      ("unbound" cl-cc/runtime:+val-unbound+ #x7FFF000000000002))
    "NaN-boxing singleton constants have expected 64-bit bit patterns (~A)."
    (label const-sym expected-bits)
  (declare (ignore label))
  (expect (symbol-value const-sym) :to-equal expected-bits))

;;; ------------------------------------------------------------
;;; val-nil-p / val-t-p / val-unbound-p
;;; ------------------------------------------------------------
(it-sequential-each (("nil-recognizes-nil" cl-cc/runtime::val-nil-p cl-cc/runtime:+val-nil+ t)
                      ("nil-rejects-t" cl-cc/runtime::val-nil-p cl-cc/runtime:+val-t+ nil)
                      ("t-recognizes-t" cl-cc/runtime::val-t-p cl-cc/runtime:+val-t+ t)
                      ("t-rejects-nil" cl-cc/runtime::val-t-p cl-cc/runtime:+val-nil+ nil)
                      ("unbound-recognizes" cl-cc/runtime::val-unbound-p cl-cc/runtime:+val-unbound+ t)
                      ("unbound-rejects-nil" cl-cc/runtime::val-unbound-p cl-cc/runtime:+val-nil+ nil))
    "val-nil-p, val-t-p, val-unbound-p each recognize their own sentinel and reject others (~A)."
    (label pred-fn val-sym expected-truthy)
  (declare (ignore label))
  (let ((val (symbol-value val-sym)))
    (if expected-truthy
        (expect (funcall pred-fn val) :to-be-truthy)
        (expect (funcall pred-fn val) :to-be-falsy))))

;;; ------------------------------------------------------------
;;; Fixnum encode/decode round-trip
;;; ------------------------------------------------------------
(it-sequential-each (("zero" 0)
                      ("positive" 42)
                      ("negative" -1)
                      ("large-positive" 1125899906842623)
                      ("large-negative" -1125899906842624))
    "encode-fixnum / decode-fixnum round-trips for representative integer values (~A)."
    (label n)
  (declare (ignore label))
  (expect
    (cl-cc/runtime::decode-fixnum (cl-cc/runtime::encode-fixnum n))
    :to-equal
    n))

(it-sequential
  "Native checked arithmetic helpers allocate bignums and coerce back to fixnum when possible."
  (let* ((max-fix (1- (ash 1 50)))
         (min-fix (- (ash 1 50)))
         (one (cl-cc/runtime::encode-fixnum 1))
         (big-add
        (cl-cc/runtime::rt-native-bignum-add (cl-cc/runtime::encode-fixnum max-fix) one))
         (big-sub
        (cl-cc/runtime::rt-native-bignum-sub (cl-cc/runtime::encode-fixnum min-fix) one))
         (big-mul
        (cl-cc/runtime::rt-native-bignum-mul
          (cl-cc/runtime::encode-fixnum (ash 1 30))
          (cl-cc/runtime::encode-fixnum (ash 1 30)))))
    (expect
      (cl-cc/runtime::rt-native-bignum-to-integer big-add)
      :to-equal
      (ash 1 50))
    (expect
      (cl-cc/runtime::rt-native-bignum-to-integer big-sub)
      :to-equal
      (1- min-fix))
    (expect
      (cl-cc/runtime::rt-native-bignum-to-integer big-mul)
      :to-equal
      (ash 1 60))
    (expect
      (cl-cc/runtime::decode-fixnum
        (cl-cc/runtime::rt-native-bignum-sub
          (cl-cc/runtime::rt-native-integer->value (ash 1 50))
          (cl-cc/runtime::rt-native-integer->value (- (ash 1 50) 42))))
      :to-equal
      42)))

;;; ------------------------------------------------------------
;;; val-fixnum-p
;;; ------------------------------------------------------------
(it-sequential-each (("zero" 0)
                      ("positive" 100)
                      ("negative" -100))
    "val-fixnum-p recognises encoded fixnums of all sign classes (~A)."
    (label n)
  (declare (ignore label))
  (expect
    (cl-cc/runtime::val-fixnum-p (cl-cc/runtime::encode-fixnum n))
    :to-be-truthy))

(it-sequential-each (("nil" cl-cc/runtime:+val-nil+)
                      ("t" cl-cc/runtime:+val-t+))
    "val-fixnum-p rejects special sentinels (~A)."
    (label val-sym)
  (declare (ignore label))
  (expect (cl-cc/runtime::val-fixnum-p (symbol-value val-sym)) :to-be-falsy))

;;; ------------------------------------------------------------
;;; Character encode/decode round-trip
;;; ------------------------------------------------------------
(it-sequential-each (("ascii" 65)
                      ("nul" 0)
                      ("unicode" #x1F600))
    "encode-char / decode-char round-trips for ASCII, NUL, and Unicode codepoints (~A)."
    (label codepoint)
  (declare (ignore label))
  (let ((c (code-char codepoint)))
    (expect (cl-cc/runtime::decode-char (cl-cc/runtime::encode-char c)) :to-equal c)))

;;; ------------------------------------------------------------
;;; val-char-p
;;; ------------------------------------------------------------
(it-sequential-each (("encoded-char" :encoded-char-x t)
                      ("nil-sentinel" :val-nil nil)
                      ("encoded-fixnum" :encoded-fixnum-65 nil))
    "val-char-p recognizes encoded chars and rejects non-char values (~A)."
    (label kind expected-truthy)
  (declare (ignore label))
  (let ((val (ecase kind
               (:encoded-char-x (cl-cc/runtime::encode-char #\x))
               (:val-nil cl-cc/runtime:+val-nil+)
               (:encoded-fixnum-65 (cl-cc/runtime::encode-fixnum 65)))))
    (if expected-truthy
        (expect (cl-cc/runtime::val-char-p val) :to-be-truthy)
        (expect (cl-cc/runtime::val-char-p val) :to-be-falsy))))

;;; ------------------------------------------------------------
;;; Double encode/decode round-trip
;;; ------------------------------------------------------------
(it-sequential-each (("zero" 0.0d0)
                      ("positive" 3.14d0)
                      ("negative" -0.1d0))
    "encode-double / decode-double round-trips for representative float values (~A)."
    (label d)
  (declare (ignore label))
  (expect
    (cl-cc/runtime::decode-double (cl-cc/runtime::encode-double d))
    :to-equal
    d))

;;; ------------------------------------------------------------
;;; val-double-p
;;; ------------------------------------------------------------
(it-sequential
  "val-double-p recognises an encoded double with non-zero mantissa low bits.
   NOTE: doubles like 1.5d0 whose low 13 mantissa bits are zero are
   indistinguishable from fixnums by bit pattern alone; use 0.1d0 instead."
  (expect
    (cl-cc/runtime::val-double-p (cl-cc/runtime::encode-double 0.1d0))
    :to-be-truthy))

(it-sequential-each (("fixnum" :encoded-fixnum-42)
                      ("nil" :val-nil))
    "val-double-p rejects non-double values (~A)."
    (label kind)
  (declare (ignore label))
  (let ((val (ecase kind
               (:encoded-fixnum-42 (cl-cc/runtime::encode-fixnum 42))
               (:val-nil cl-cc/runtime:+val-nil+))))
    (expect (cl-cc/runtime::val-double-p val) :to-be-falsy)))

;;; ------------------------------------------------------------
;;; Pointer encode/decode
;;; ------------------------------------------------------------
(it-sequential-each (("object" #x0000DEADBEEF cl-cc/runtime:+tag-object+)
                      ("cons" #x0000CAFE1234 cl-cc/runtime:+tag-cons+)
                      ("function" #x0000000100FF cl-cc/runtime:+tag-function+))
    "encode-pointer / decode-pointer round-trips for each pointer tag (~A)."
    (label addr tag-sym)
  (declare (ignore label))
  (let* ((tag (symbol-value tag-sym))
         (v (cl-cc/runtime::encode-pointer addr tag)))
    (expect (cl-cc/runtime::decode-pointer v) :to-equal addr)))

;;; ------------------------------------------------------------
;;; val-pointer-p / sub-tag predicates
;;; ------------------------------------------------------------
(it-sequential-each (("object" cl-cc/runtime:+tag-object+)
                      ("cons" cl-cc/runtime:+tag-cons+)
                      ("string" cl-cc/runtime:+tag-string+))
    "val-pointer-p recognises all pointer-tagged values (~A)."
    (label tag-sym)
  (declare (ignore label))
  (let ((tag (symbol-value tag-sym)))
    (expect
      (cl-cc/runtime::val-pointer-p (cl-cc/runtime::encode-pointer #x1000 tag))
      :to-be-truthy)))

(it-sequential-each (("nil" :val-nil)
                      ("char" :encoded-char-a))
    "val-pointer-p rejects sentinels and non-pointer-tagged values (~A)."
    (label kind)
  (declare (ignore label))
  (let ((val (ecase kind
               (:val-nil cl-cc/runtime:+val-nil+)
               (:encoded-char-a (cl-cc/runtime::encode-char #\A)))))
    (expect (cl-cc/runtime::val-pointer-p val) :to-be-falsy)))

(it-sequential-each (("object" cl-cc/runtime:+tag-object+ cl-cc/runtime::val-object-p)
                      ("cons" cl-cc/runtime:+tag-cons+ cl-cc/runtime::val-cons-p)
                      ("symbol" cl-cc/runtime:+tag-symbol+ cl-cc/runtime::val-symbol-p)
                      ("function" cl-cc/runtime:+tag-function+ cl-cc/runtime::val-function-p)
                      ("string" cl-cc/runtime:+tag-string+ cl-cc/runtime::val-string-p))
    "Each sub-tag predicate recognises its own tag and rejects others (~A)."
    (label tag-sym pred)
  (declare (ignore label))
  (let* ((tag (symbol-value tag-sym))
         (v (cl-cc/runtime::encode-pointer #x1000 tag)))
    (expect (funcall pred v) :to-be-truthy)))

;;; ------------------------------------------------------------
;;; No collisions between types
;;; ------------------------------------------------------------
(it-sequential
  "nil constant and char base are distinct bit patterns."
  (expect (/= cl-cc/runtime:+val-nil+ cl-cc/runtime:+tag-char+) :to-be-truthy))

(it-sequential-each (("cons" cl-cc/runtime:+tag-cons+)
                      ("function" cl-cc/runtime:+tag-function+))
    "Pointer tag upper-16 bits differ from the char upper-16 bits (#x7FFE) (~A)."
    (label tag-sym)
  (declare (ignore label))
  (let* ((tag (symbol-value tag-sym))
         (ptr-v (cl-cc/runtime::encode-pointer 0 tag))
         (char-v (cl-cc/runtime::encode-char (code-char 0))))
    (expect (/= (ash ptr-v -48) (ash char-v -48)) :to-be-truthy)))

;;; ------------------------------------------------------------
;;; encode-bool
;;; ------------------------------------------------------------
(it-sequential-each (("t" t cl-cc/runtime:+val-t+)
                      ("nil" nil cl-cc/runtime:+val-nil+)
                      ("truthy" 42 cl-cc/runtime:+val-t+))
    "encode-bool maps CL truthiness to val-t or val-nil (~A)."
    (label cl-val expected-tag-sym)
  (declare (ignore label))
  (expect (cl-cc/runtime::encode-bool cl-val) :to-equal (symbol-value expected-tag-sym)))

;;; ------------------------------------------------------------
;;; cl-value->val / val->cl-value round-trips
;;; ------------------------------------------------------------
(it-sequential-each (("fixnum" 99)
                      ("char" #\Z))
    "cl-value->val / val->cl-value round-trip for scalar CL values (~A)."
    (label cl-val)
  (declare (ignore label))
  (expect
    (cl-cc/runtime::val->cl-value (cl-cc/runtime::cl-value->val cl-val))
    :to-equal
    cl-val))

(it-sequential
  "cl-value->val nil gives +val-nil+; val->cl-value returns nil."
  (expect (cl-cc/runtime::cl-value->val nil) :to-equal cl-cc/runtime:+val-nil+)
  (expect (cl-cc/runtime::val->cl-value cl-cc/runtime:+val-nil+) :to-equal nil))

(it-sequential
  "cl-value->val t gives +val-t+; val->cl-value returns t."
  (expect (cl-cc/runtime::cl-value->val t) :to-equal cl-cc/runtime:+val-t+)
  (expect (cl-cc/runtime::val->cl-value cl-cc/runtime:+val-t+) :to-equal t))

(it-sequential
  "cl-value->val double-float round-trips."
  (expect
    (cl-cc/runtime::val->cl-value (cl-cc/runtime::cl-value->val 2.71828d0))
    :to-equal
    2.71828d0))
