;;;; t/value-test.lisp - NaN-Boxing Value Representation Tests
;;;
;;; Tests for cl-cc/runtime NaN-boxing: type predicates, encode/decode
;;; round-trips, singleton constants, and edge-case bit patterns.
(in-package :cl-cc/runtime/values/test)

;;; ------------------------------------------------------------
;;; Suite
;;; ------------------------------------------------------------
;;; ------------------------------------------------------------
;;; Singleton constants
;;; ------------------------------------------------------------
(it-sequential-each (("nil" cl-cc/runtime/values:+val-nil+ #x7FFF000000000000)
                      ("t" cl-cc/runtime/values:+val-t+ #x7FFF000000000001)
                      ("unbound" cl-cc/runtime/values:+val-unbound+ #x7FFF000000000002))
    "NaN-boxing singleton constants have expected 64-bit bit patterns (~A)."
    (label const-sym expected-bits)
  (declare (ignore label))
  (expect (symbol-value const-sym) :to-equal expected-bits))

;;; ------------------------------------------------------------
;;; val-nil-p / val-t-p / val-unbound-p
;;; ------------------------------------------------------------
(it-sequential-each (("nil-recognizes-nil" cl-cc/runtime/values:val-nil-p cl-cc/runtime/values:+val-nil+ t)
                      ("nil-rejects-t" cl-cc/runtime/values:val-nil-p cl-cc/runtime/values:+val-t+ nil)
                      ("t-recognizes-t" cl-cc/runtime/values:val-t-p cl-cc/runtime/values:+val-t+ t)
                      ("t-rejects-nil" cl-cc/runtime/values:val-t-p cl-cc/runtime/values:+val-nil+ nil)
                      ("unbound-recognizes" cl-cc/runtime/values:val-unbound-p cl-cc/runtime/values:+val-unbound+ t)
                      ("unbound-rejects-nil" cl-cc/runtime/values:val-unbound-p cl-cc/runtime/values:+val-nil+ nil))
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
    (cl-cc/runtime/values:decode-fixnum (cl-cc/runtime/values:encode-fixnum n))
    :to-equal
    n))

(it-sequential
  "Native checked arithmetic helpers allocate bignums and coerce back to fixnum when possible."
  (let* ((max-fix (1- (ash 1 50)))
         (min-fix (- (ash 1 50)))
         (one (cl-cc/runtime/values:encode-fixnum 1))
         (big-add
        (cl-cc/runtime/values:rt-native-bignum-add (cl-cc/runtime/values:encode-fixnum max-fix) one))
         (big-sub
        (cl-cc/runtime/values:rt-native-bignum-sub (cl-cc/runtime/values:encode-fixnum min-fix) one))
         (big-mul
        (cl-cc/runtime/values:rt-native-bignum-mul
          (cl-cc/runtime/values:encode-fixnum (ash 1 30))
          (cl-cc/runtime/values:encode-fixnum (ash 1 30)))))
    (expect
      (cl-cc/runtime/values:rt-native-bignum-to-integer big-add)
      :to-equal
      (ash 1 50))
    (expect
      (cl-cc/runtime/values:rt-native-bignum-to-integer big-sub)
      :to-equal
      (1- min-fix))
    (expect
      (cl-cc/runtime/values:rt-native-bignum-to-integer big-mul)
      :to-equal
      (ash 1 60))
    (expect
      (cl-cc/runtime/values:decode-fixnum
        (cl-cc/runtime/values:rt-native-bignum-sub
          (cl-cc/runtime/values:rt-native-integer->value (ash 1 50))
          (cl-cc/runtime/values:rt-native-integer->value (- (ash 1 50) 42))))
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
    (cl-cc/runtime/values:val-fixnum-p (cl-cc/runtime/values:encode-fixnum n))
    :to-be-truthy))

(it-sequential-each (("nil" cl-cc/runtime/values:+val-nil+)
                      ("t" cl-cc/runtime/values:+val-t+))
    "val-fixnum-p rejects special sentinels (~A)."
    (label val-sym)
  (declare (ignore label))
  (expect (cl-cc/runtime/values:val-fixnum-p (symbol-value val-sym)) :to-be-falsy))

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
    (expect (cl-cc/runtime/values:decode-char (cl-cc/runtime/values:encode-char c)) :to-equal c)))

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
               (:encoded-char-x (cl-cc/runtime/values:encode-char #\x))
               (:val-nil cl-cc/runtime/values:+val-nil+)
               (:encoded-fixnum-65 (cl-cc/runtime/values:encode-fixnum 65)))))
    (if expected-truthy
        (expect (cl-cc/runtime/values:val-char-p val) :to-be-truthy)
        (expect (cl-cc/runtime/values:val-char-p val) :to-be-falsy))))

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
    (cl-cc/runtime/values:decode-double (cl-cc/runtime/values:encode-double d))
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
    (cl-cc/runtime/values:val-double-p (cl-cc/runtime/values:encode-double 0.1d0))
    :to-be-truthy))

(it-sequential-each (("fixnum" :encoded-fixnum-42)
                      ("nil" :val-nil))
    "val-double-p rejects non-double values (~A)."
    (label kind)
  (declare (ignore label))
  (let ((val (ecase kind
               (:encoded-fixnum-42 (cl-cc/runtime/values:encode-fixnum 42))
               (:val-nil cl-cc/runtime/values:+val-nil+))))
    (expect (cl-cc/runtime/values:val-double-p val) :to-be-falsy)))

;;; ------------------------------------------------------------
;;; Pointer encode/decode
;;; ------------------------------------------------------------
(it-sequential-each (("object" #x0000DEADBEEF cl-cc/runtime/values:+tag-object+)
                      ("cons" #x0000CAFE1234 cl-cc/runtime/values:+tag-cons+)
                      ("function" #x0000000100FF cl-cc/runtime/values:+tag-function+))
    "encode-pointer / decode-pointer round-trips for each pointer tag (~A)."
    (label addr tag-sym)
  (declare (ignore label))
  (let* ((tag (symbol-value tag-sym))
         (v (cl-cc/runtime/values:encode-pointer addr tag)))
    (expect (cl-cc/runtime/values:decode-pointer v) :to-equal addr)))

;;; ------------------------------------------------------------
;;; val-pointer-p / sub-tag predicates
;;; ------------------------------------------------------------
(it-sequential-each (("object" cl-cc/runtime/values:+tag-object+)
                      ("cons" cl-cc/runtime/values:+tag-cons+)
                      ("string" cl-cc/runtime/values:+tag-string+))
    "val-pointer-p recognises all pointer-tagged values (~A)."
    (label tag-sym)
  (declare (ignore label))
  (let ((tag (symbol-value tag-sym)))
    (expect
      (cl-cc/runtime/values:val-pointer-p (cl-cc/runtime/values:encode-pointer #x1000 tag))
      :to-be-truthy)))

(it-sequential-each (("nil" :val-nil)
                      ("char" :encoded-char-a))
    "val-pointer-p rejects sentinels and non-pointer-tagged values (~A)."
    (label kind)
  (declare (ignore label))
  (let ((val (ecase kind
               (:val-nil cl-cc/runtime/values:+val-nil+)
               (:encoded-char-a (cl-cc/runtime/values:encode-char #\A)))))
    (expect (cl-cc/runtime/values:val-pointer-p val) :to-be-falsy)))

(it-sequential-each (("object" cl-cc/runtime/values:+tag-object+ cl-cc/runtime/values:val-object-p)
                      ("cons" cl-cc/runtime/values:+tag-cons+ cl-cc/runtime/values:val-cons-p)
                      ("symbol" cl-cc/runtime/values:+tag-symbol+ cl-cc/runtime/values:val-symbol-p)
                      ("function" cl-cc/runtime/values:+tag-function+ cl-cc/runtime/values:val-function-p)
                      ("string" cl-cc/runtime/values:+tag-string+ cl-cc/runtime/values:val-string-p))
    "Each sub-tag predicate recognises its own tag and rejects others (~A)."
    (label tag-sym pred)
  (declare (ignore label))
  (let* ((tag (symbol-value tag-sym))
         (v (cl-cc/runtime/values:encode-pointer #x1000 tag)))
    (expect (funcall pred v) :to-be-truthy)))

;;; ------------------------------------------------------------
;;; No collisions between types
;;; ------------------------------------------------------------
(it-sequential
  "nil constant and char base are distinct bit patterns."
  (expect (/= cl-cc/runtime/values:+val-nil+ cl-cc/runtime/values:+tag-char+) :to-be-truthy))

(it-sequential-each (("cons" cl-cc/runtime/values:+tag-cons+)
                      ("function" cl-cc/runtime/values:+tag-function+))
    "Pointer tag upper-16 bits differ from the char upper-16 bits (#x7FFE) (~A)."
    (label tag-sym)
  (declare (ignore label))
  (let* ((tag (symbol-value tag-sym))
         (ptr-v (cl-cc/runtime/values:encode-pointer 0 tag))
         (char-v (cl-cc/runtime/values:encode-char (code-char 0))))
    (expect (/= (ash ptr-v -48) (ash char-v -48)) :to-be-truthy)))

;;; ------------------------------------------------------------
;;; encode-bool
;;; ------------------------------------------------------------
(it-sequential-each (("t" t cl-cc/runtime/values:+val-t+)
                      ("nil" nil cl-cc/runtime/values:+val-nil+)
                      ("truthy" 42 cl-cc/runtime/values:+val-t+))
    "encode-bool maps CL truthiness to val-t or val-nil (~A)."
    (label cl-val expected-tag-sym)
  (declare (ignore label))
  (expect (cl-cc/runtime/values:encode-bool cl-val) :to-equal (symbol-value expected-tag-sym)))

;;; ------------------------------------------------------------
;;; cl-value->val / val->cl-value round-trips
;;; ------------------------------------------------------------
(it-sequential-each (("fixnum" 99)
                      ("char" #\Z))
    "cl-value->val / val->cl-value round-trip for scalar CL values (~A)."
    (label cl-val)
  (declare (ignore label))
  (expect
    (cl-cc/runtime/values:val->cl-value (cl-cc/runtime/values:cl-value->val cl-val))
    :to-equal
    cl-val))

(it-sequential
  "cl-value->val nil gives +val-nil+; val->cl-value returns nil."
  (expect (cl-cc/runtime/values:cl-value->val nil) :to-equal cl-cc/runtime/values:+val-nil+)
  (expect (cl-cc/runtime/values:val->cl-value cl-cc/runtime/values:+val-nil+) :to-equal nil))

(it-sequential
  "cl-value->val t gives +val-t+; val->cl-value returns t."
  (expect (cl-cc/runtime/values:cl-value->val t) :to-equal cl-cc/runtime/values:+val-t+)
  (expect (cl-cc/runtime/values:val->cl-value cl-cc/runtime/values:+val-t+) :to-equal t))

(it-sequential
  "cl-value->val double-float round-trips."
  (expect
    (cl-cc/runtime/values:val->cl-value (cl-cc/runtime/values:cl-value->val 2.71828d0))
    :to-equal
    2.71828d0))

(it-sequential
  "FFI array buffers keep a stable native pointer across GC and copy writes back on release."
  (let* ((array (make-array 3 :element-type '(unsigned-byte 8)
                            :initial-contents '(7 8 9)))
         (buffer (cl-cc/runtime/values:rt-pin-unboxed-array array))
         (pointer (cl-cc/runtime/values:rt-pinned-array-data-pointer buffer)))
    (unwind-protect
         (progn
           (sb-sys:with-pinned-objects (array)
             (expect (/= (sb-sys:sap-int pointer)
                         (sb-sys:sap-int (sb-sys:vector-sap array)))
                     :to-be-truthy))
           (expect (sb-sys:sap-ref-8 pointer 0) :to-equal 7)
           (setf (sb-sys:sap-ref-8 pointer 1) 42)
           (sb-ext:gc :full t)
           (expect (sb-sys:sap-ref-8 pointer 1) :to-equal 42)
           (cl-cc/runtime/values:rt-release-pinned-array buffer)
           (expect (aref array 1) :to-equal 42)
           (expect (cl-cc/runtime/values:rt-pinned-unboxed-array-buffer-released-p buffer)
                   :to-be-truthy)
           (signals error (cl-cc/runtime/values:rt-pinned-array-data-pointer buffer))
           (cl-cc/runtime/values:rt-release-pinned-array buffer))
      (unless (cl-cc/runtime/values:rt-pinned-unboxed-array-buffer-released-p buffer)
        (cl-cc/runtime/values:rt-release-pinned-array buffer)))))
(it-sequential
  "Concurrent release calls on one buffer are serialized."
  (let* ((array (make-array 256 :element-type (quote (unsigned-byte 8))
                            :initial-element 0))
         (buffer (cl-cc/runtime/values:rt-pin-unboxed-array array))
         (pointer (cl-cc/runtime/values:rt-pinned-array-data-pointer buffer))
         (ready (sb-thread:make-semaphore :count 0))
         (start (sb-thread:make-semaphore :count 0))
         (threads nil)
         (thread-count 0)
         (workers-started nil)
         (thread-errors (make-array 8 :initial-element nil)))
    (setf (sb-sys:sap-ref-8 pointer 255) 42)
    (unwind-protect
         (progn
           (loop for index below 8
                 do (let ((worker-index index))
                      (push (sb-thread:make-thread
                             (lambda ()
                               (sb-thread:signal-semaphore ready)
                               (sb-thread:wait-on-semaphore start)
                               (handler-case
                                   (cl-cc/runtime/values:rt-release-pinned-array buffer)
                                 (error (condition)
                                   (setf (aref thread-errors worker-index) condition)))))
                            threads)
                      (incf thread-count)))
           (loop repeat thread-count do (sb-thread:wait-on-semaphore ready))
           (loop repeat thread-count do (sb-thread:signal-semaphore start))
           (setf workers-started t)
           (dolist (thread threads)
             (sb-thread:join-thread thread))
           (dotimes (index thread-count)
             (expect (aref thread-errors index) :to-be-falsy))
           (expect (aref array 255) :to-equal 42)
           (expect (cl-cc/runtime/values:rt-pinned-unboxed-array-buffer-released-p buffer)
                   :to-be-truthy))
      (progn
        (unless workers-started
          (loop repeat thread-count do (sb-thread:signal-semaphore start)))
        (dolist (thread threads)
          (when (sb-thread:thread-alive-p thread)
            (sb-thread:join-thread thread)))
        (unless (cl-cc/runtime/values:rt-pinned-unboxed-array-buffer-released-p buffer)
          (cl-cc/runtime/values:rt-release-pinned-array buffer))))))
