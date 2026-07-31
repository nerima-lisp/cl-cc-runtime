;;;; t/runtime-data-ops-test.lisp — Runtime Library Unit Tests: data operations
;;;;
;;;; Continuation of runtime-test.lisp:
;;;; list ops, array ops, arithmetic helpers, numeric predicates, and comparisons.
(in-package :cl-cc-runtime/test)

;;; ─── List Operations ───────────────────────────────────────────────────────
(defun %prepare-rt-copy-list-fixture ()
  (let ((base '(1 2 3)))
    (values base (cl-cc/runtime::rt-copy-list base))))

(it-sequential
  "rt-cons/car/cdr create cons; rt-rplaca/rt-rplacd mutate in place."
  (let ((c (cl-cc/runtime::rt-cons 1 2)))
    (expect (cl-cc/runtime::rt-car c) :to-equal 1)
    (expect (cl-cc/runtime::rt-cdr c) :to-equal 2)
    (cl-cc/runtime::rt-rplaca c 10)
    (cl-cc/runtime::rt-rplacd c 20)
    (expect (cl-cc/runtime::rt-car c) :to-equal 10)
    (expect (cl-cc/runtime::rt-cdr c) :to-equal 20)))

(it-sequential
  "rt-copy-list returns a COW-capable value that preserves list reads."
  (multiple-value-bind (base copy) (%prepare-rt-copy-list-fixture)
    (declare (ignore base))
    (expect (cl-cc/runtime::rt-car copy) :to-equal 1)
    (expect (cl-cc/runtime::rt-cdr copy) :to-equal '(2 3))
    (expect (cl-cc/runtime::rt-list-length copy) :to-equal 3)))

(it-sequential
  "Mutating a copied COW list does not mutate the original shared list."
  (multiple-value-bind (base copy) (%prepare-rt-copy-list-fixture)
    (cl-cc/runtime::rt-rplaca copy 99)
    (expect (cl-cc/runtime::rt-car copy) :to-equal 99)
    (expect (car base) :to-equal 1)))

(it-sequential
  "rt-pop-list returns head+tail; rt-push-list conses onto front."
  (multiple-value-bind (head tail) (cl-cc/runtime::rt-pop-list '(a b c))
    (expect head :to-be 'a)
    (expect tail :to-equal '(b c)))
  (expect (cl-cc/runtime::rt-push-list 'x '(a b)) :to-equal '(x a b)))

(it-sequential-each (("nil-end"   nil  1)
                      ("non-empty" (1) 0))
    "rt-endp: 1 for nil (end of list); 0 for non-empty list (~A)."
    (label input expected)
  (declare (ignore label))
  (expect (cl-cc/runtime::rt-endp input) :to-equal expected))

(it-sequential-each (("equal"     (1 2) (1 2) 1)
                      ("not-equal" (1 2) (1 3) 0))
    "rt-equal: 1 when structurally equal; 0 when not (~A)."
    (label a b expected)
  (declare (ignore label))
  (expect (cl-cc/runtime::rt-equal a b) :to-equal expected))

;;; ─── Array Operations ─────────────────────────────────────────────────────
(it-sequential
  "rt-make-array: correct length; :initial-element initializes all slots."
  (let ((a5 (cl-cc/runtime::rt-make-array 5))
        (a3 (cl-cc/runtime::rt-make-array 3 :initial-element 0)))
    (expect (cl-cc/runtime::rt-array-length a5) :to-equal 5)
    (expect (cl-cc/runtime::rt-aref a3 0) :to-equal 0)))

(it-sequential
  "rt-aset/rt-aref, rt-svref/rt-svset, rt-bit-set/rt-bit-access all mutate correctly."
  (let ((a (cl-cc/runtime::rt-make-array 3 :initial-element 0)))
    (cl-cc/runtime::rt-aset a 1 42)
    (expect (cl-cc/runtime::rt-aref a 1) :to-equal 42))
  (let ((v (vector 1 2 3)))
    (expect (cl-cc/runtime::rt-svref v 1) :to-equal 2)
    (cl-cc/runtime::rt-svset v 1 99)
    (expect (cl-cc/runtime::rt-svref v 1) :to-equal 99))
  (let ((bv (make-array 4 :element-type 'bit :initial-element 0)))
    (cl-cc/runtime::rt-bit-set bv 2 1)
    (expect (cl-cc/runtime::rt-bit-access bv 2) :to-equal 1)
    (expect (cl-cc/runtime::rt-bit-access bv 0) :to-equal 0)))

;;; ─── Arithmetic Helpers ────────────────────────────────────────────────────
(it-sequential-each (("add" cl-cc/runtime::rt-add 3  4   7)
                      ("sub" cl-cc/runtime::rt-sub 3  4  -1)
                      ("mul" cl-cc/runtime::rt-mul 3  4  12)
                      ("div" cl-cc/runtime::rt-div 5  2   5/2)
                      ("mod" cl-cc/runtime::rt-mod 7  3   1)
                      ("rem" cl-cc/runtime::rt-rem 7  3   1))
    "rt-add/sub/mul/div/mod/rem: binary arithmetic operations (~A)."
    (label fn a b expected)
  (declare (ignore label))
  (expect (funcall fn a b) :to-equal expected))

(it-sequential-each (("neg"    cl-cc/runtime::rt-neg     5   -5)
                      ("abs"    cl-cc/runtime::rt-abs    -5    5)
                      ("inc"    cl-cc/runtime::rt-inc     5    6)
                      ("dec"    cl-cc/runtime::rt-dec     5    4)
                      ("lognot" cl-cc/runtime::rt-lognot  42  -43))
    "rt-neg/abs/inc/dec/lognot: unary arithmetic and bitwise operations (~A)."
    (label fn input expected)
  (declare (ignore label))
  (expect (funcall fn input) :to-equal expected))

(it-sequential-each (("nil"     nil  1)
                      ("true"    t    0)
                      ("integer" 42   0))
    "rt-not: 1 for falsy (nil); 0 for truthy (t, integer) (~A)."
    (label input expected)
  (declare (ignore label))
  (expect (cl-cc/runtime::rt-not input) :to-equal expected))

(it-sequential-each (("evenp-t"  cl-cc/runtime::rt-evenp  4  1)
                      ("evenp-f"  cl-cc/runtime::rt-evenp  3  0)
                      ("oddp-t"   cl-cc/runtime::rt-oddp   3  1)
                      ("oddp-f"   cl-cc/runtime::rt-oddp   4  0)
                      ("zerop-t"  cl-cc/runtime::rt-zerop  0  1)
                      ("zerop-f"  cl-cc/runtime::rt-zerop  1  0)
                      ("plusp-t"  cl-cc/runtime::rt-plusp   5  1)
                      ("plusp-f"  cl-cc/runtime::rt-plusp  -1  0)
                      ("minusp-t" cl-cc/runtime::rt-minusp -1  1)
                      ("minusp-f" cl-cc/runtime::rt-minusp  1  0))
    "Numeric predicates return 1/0 (~A)."
    (label pred-fn input expected)
  (declare (ignore label))
  (expect (funcall pred-fn input) :to-equal expected))

;;; ─── Comparisons ───────────────────────────────────────────────────────────
(it-sequential-each (("lt-t"     cl-cc/runtime::rt-lt     1 2 1)
                      ("lt-f"     cl-cc/runtime::rt-lt     2 1 0)
                      ("gt-t"     cl-cc/runtime::rt-gt     2 1 1)
                      ("gt-f"     cl-cc/runtime::rt-gt     1 2 0)
                      ("le-eq"    cl-cc/runtime::rt-le     2 2 1)
                      ("ge-eq"    cl-cc/runtime::rt-ge     2 2 1)
                      ("num-eq-t" cl-cc/runtime::rt-num-eq 5 5 1)
                      ("num-eq-f" cl-cc/runtime::rt-num-eq 5 6 0)
                      ("eq-t"     cl-cc/runtime::rt-eq     :a :a 1)
                      ("eq-f"     cl-cc/runtime::rt-eq     :a :b 0)
                      ("eql-t"    cl-cc/runtime::rt-eql    42 42 1)
                      ("eql-f"    cl-cc/runtime::rt-eql    42 43 0))
    "Comparison helpers return 1/0 (~A)."
    (label cmp-fn a b expected)
  (declare (ignore label))
  (expect (funcall cmp-fn a b) :to-equal expected))

;;; ─── Runtime Region Operations ─────────────────────────────────────────────
(it-sequential
  "rt-with-region/alloc/deref enforce region lifetime at runtime."
  (let (escaped-ref)
    (cl-cc/runtime::rt-with-region
      (region)
      (expect (cl-cc/runtime::rt-region-active-p region) :to-be-truthy)
      (let ((ref (cl-cc/runtime::rt-region-alloc region 42)))
        (setf escaped-ref ref)
        (expect (cl-cc/runtime::rt-region-ref-valid-p ref) :to-be-truthy)
        (expect (cl-cc/runtime::rt-region-deref ref) :to-equal 42)))
    (expect (cl-cc/runtime::rt-region-ref-valid-p escaped-ref) :to-be-falsy)
    (signals error (cl-cc/runtime::rt-region-deref escaped-ref))))

(it-sequential
  "Region allocation advances bump index and close resets usage."
  (let ((r (cl-cc/runtime::rt-make-region)))
    (expect (cl-cc/runtime::rt-region-used r) :to-equal 0)
    (let ((cap (cl-cc/runtime::rt-region-capacity r)))
      (expect (> cap 0) :to-be-truthy)
      (cl-cc/runtime::rt-region-alloc r :a)
      (cl-cc/runtime::rt-region-alloc r :b)
      (expect (cl-cc/runtime::rt-region-used r) :to-equal 2)
      (cl-cc/runtime::rt-close-region r)
      (expect (cl-cc/runtime::rt-region-used r) :to-equal 0))))
