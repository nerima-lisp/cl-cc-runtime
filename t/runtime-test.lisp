;;;; t/runtime-test.lisp — Runtime Library Unit Tests
;;;;
;;;; Tests for src/runtime/runtime.lisp: tagged pointers, multiple values buffer,
;;;; closure support, type predicates, list ops, array ops, arithmetic helpers,
;;;; string/char ops, symbol ops, hash table ops, and I/O wrappers.
(in-package :cl-cc-runtime/test)

;;; ─── Tagged Pointers ───────────────────────────────────────────────────────
(it-sequential-each (("zero" 0 0)
                      ("one" 1 8)
                      ("forty-two" 42 336))
    "rt-tag-fixnum shifts left by 3 bits; tag is 000 for fixnum (~A)."
    (label n expected)
  (declare (ignore label))
  (expect (cl-cc/runtime::rt-tag-fixnum n) :to-equal expected))

(it-sequential
  "rt-untag-fixnum reverses rt-tag-fixnum."
  (dolist (n '(0 1 42 -7 1000000))
    (expect
      (cl-cc/runtime::rt-untag-fixnum (cl-cc/runtime::rt-tag-fixnum n))
      :to-equal
      n)))

(it-sequential-each (("fixnum-8" 8 0)
                      ("cons-9" 9 1)
                      ("max-15" 15 7)
                      ("plain-5" 5 5))
    "rt-tag-bits returns the low 3 bits (~A)."
    (label tagged expected-bits)
  (declare (ignore label))
  (expect (cl-cc/runtime::rt-tag-bits tagged) :to-equal expected-bits))

(it-sequential
  "All 8 tag constants have distinct values 0-7."
  (let ((tags
        (list
          cl-cc/runtime:+tag-fixnum+
          cl-cc/runtime:+rt-tag-cons+
          cl-cc/runtime:+rt-tag-symbol+
          cl-cc/runtime:+rt-tag-function+
          cl-cc/runtime:+tag-character+
          cl-cc/runtime:+tag-array+
          cl-cc/runtime:+rt-tag-string+
          cl-cc/runtime:+tag-other+)))
    (expect (length (remove-duplicates tags)) :to-equal 8)
    (dolist (tag tags)
      (expect (and (>= tag 0) (<= tag 7)) :to-be-truthy))))

;;; ─── Multiple Values Buffer ────────────────────────────────────────────────
(it-sequential
  "rt-values-clear resets to empty; rt-values-push increments count."
  (cl-cc/runtime::rt-values-clear)
  (expect (cl-cc/runtime::rt-values-count) :to-equal 0)
  (cl-cc/runtime::rt-values-push 10)
  (cl-cc/runtime::rt-values-push 20)
  (expect (cl-cc/runtime::rt-values-count) :to-equal 2))

(it-sequential
  "rt-values-ref retrieves by index."
  (cl-cc/runtime::rt-values-clear)
  (cl-cc/runtime::rt-values-push :a)
  (cl-cc/runtime::rt-values-push :b)
  (cl-cc/runtime::rt-values-push :c)
  (expect (cl-cc/runtime::rt-values-ref 0) :to-be :a)
  (expect (cl-cc/runtime::rt-values-ref 1) :to-be :b)
  (expect (cl-cc/runtime::rt-values-ref 2) :to-be :c))

(it-sequential
  "rt-values-to-list returns the full buffer."
  (cl-cc/runtime::rt-values-clear)
  (cl-cc/runtime::rt-values-push 1)
  (cl-cc/runtime::rt-values-push 2)
  (expect (cl-cc/runtime::rt-values-to-list) :to-equal '(1 2)))

(it-sequential-each (("list" (10 20 30) 3 10)
                      ("atom" 42 1 42))
    "rt-spread-values: list spreads all elements; atom pushes one (~A)."
    (label input expected-count expected-first)
  (declare (ignore label))
  (cl-cc/runtime::rt-values-clear)
  (cl-cc/runtime::rt-spread-values input)
  (expect (cl-cc/runtime::rt-values-count) :to-equal expected-count)
  (expect (cl-cc/runtime::rt-values-ref 0) :to-equal expected-first))

(it-sequential-each (("empty" nil 99 1 99)
                      ("non-empty" 1 99 1 1))
    "rt-ensure-values pushes val when empty; is a no-op when buffer already has a value (~A)."
    (label pre-val ensure-val expected-count expected-ref0)
  (declare (ignore label))
  (cl-cc/runtime::rt-values-clear)
  (when pre-val
    (cl-cc/runtime::rt-values-push pre-val))
  (cl-cc/runtime::rt-ensure-values ensure-val)
  (expect (cl-cc/runtime::rt-values-count) :to-equal expected-count)
  (expect (cl-cc/runtime::rt-values-ref 0) :to-equal expected-ref0))

;;; ─── Closure Support ───────────────────────────────────────────────────────
(it-sequential
  "rt-make-closure returns an rt-closure-obj."
  (let ((c (cl-cc/runtime::rt-make-closure #'identity '(1 2 3))))
    (expect (cl-cc/runtime::rt-closure-obj-p c) :to-be-truthy)))

(it-sequential
  "rt-closure-ref retrieves captured values by index."
  (let ((c (cl-cc/runtime::rt-make-closure #'identity '(a b c))))
    (expect (cl-cc/runtime::rt-closure-ref c 0) :to-be 'a)
    (expect (cl-cc/runtime::rt-closure-ref c 1) :to-be 'b)
    (expect (cl-cc/runtime::rt-closure-ref c 2) :to-be 'c)))

(it-sequential-each (("closure" :closure-double (5) 10)
                      ("plain-fn" :plain-plus (3 4) 7))
    "rt-call-fn dispatches uniformly to closures and plain functions (~A)."
    (label kind args expected)
  (declare (ignore label))
  (let ((fn (ecase kind
              (:closure-double (cl-cc/runtime::rt-make-closure (lambda (x) (* x 2)) nil))
              (:plain-plus #'+))))
    (expect (apply #'cl-cc/runtime::rt-call-fn fn args) :to-equal expected)))

(it-sequential-each (("closure" :closure-add (10 5) 15)
                      ("plain-fn" :plain-times (2 3) 6))
    "rt-apply-fn applies args list uniformly to closures and plain functions (~A)."
    (label kind args expected)
  (declare (ignore label))
  (let ((fn (ecase kind
              (:closure-add (cl-cc/runtime::rt-make-closure (lambda (a b) (+ a b)) nil))
              (:plain-times #'*))))
    (expect (cl-cc/runtime::rt-apply-fn fn args) :to-equal expected)))

(it-sequential
  "With no method stack: rt-next-method-p returns nil; rt-call-next-method signals error."
  (expect (cl-cc/runtime::rt-next-method-p) :to-be-falsy)
  (signals error (cl-cc/runtime::rt-call-next-method)))

;;; ─── Type Predicates (1/0 return convention) ───────────────────────────────
(it-sequential-each (("consp-t" cl-cc/runtime::rt-consp (1 . 2) 1)
                      ("consp-f" cl-cc/runtime::rt-consp 42 0)
                      ("null-p-t" cl-cc/runtime::rt-null-p nil 1)
                      ("null-p-f" cl-cc/runtime::rt-null-p 42 0)
                      ("symbolp-t" cl-cc/runtime::rt-symbolp foo 1)
                      ("symbolp-f" cl-cc/runtime::rt-symbolp 42 0)
                      ("numberp-t" cl-cc/runtime::rt-numberp 3.14 1)
                      ("numberp-f" cl-cc/runtime::rt-numberp "hi" 0)
                      ("integerp-t" cl-cc/runtime::rt-integerp 42 1)
                      ("integerp-f" cl-cc/runtime::rt-integerp 3.14 0)
                      ("floatp-t" cl-cc/runtime::rt-floatp 1.0 1)
                      ("floatp-f" cl-cc/runtime::rt-floatp 1 0)
                      ("stringp-t" cl-cc/runtime::rt-stringp "hi" 1)
                      ("stringp-f" cl-cc/runtime::rt-stringp 42 0)
                      ("characterp-t" cl-cc/runtime::rt-characterp #\a 1)
                      ("characterp-f" cl-cc/runtime::rt-characterp 42 0)
                      ("vectorp-t" cl-cc/runtime::rt-vectorp #(1 2) 1)
                      ("vectorp-f" cl-cc/runtime::rt-vectorp 42 0)
                      ("listp-t" cl-cc/runtime::rt-listp (1) 1)
                      ("listp-nil" cl-cc/runtime::rt-listp nil 1)
                      ("listp-f" cl-cc/runtime::rt-listp 42 0)
                      ("atomp-t" cl-cc/runtime::rt-atomp 42 1)
                      ("atomp-f" cl-cc/runtime::rt-atomp (1) 0)
                      ("keywordp-t" cl-cc/runtime::rt-keywordp :foo 1)
                      ("keywordp-f" cl-cc/runtime::rt-keywordp foo 0)
                      ("hash-t" cl-cc/runtime::rt-hash-table-p :fresh-hash-table 1)
                      ("hash-f" cl-cc/runtime::rt-hash-table-p 42 0))
    "Runtime type predicates return 1 for match, 0 otherwise (~A)."
    (label pred-fn input expected)
  (declare (ignore label))
  (let ((input (if (eq input :fresh-hash-table) (make-hash-table) input)))
    (expect (funcall pred-fn input) :to-equal expected)))

(it-sequential
  "rt-functionp returns 1 for closure objects too."
  (let ((c (cl-cc/runtime::rt-make-closure #'identity nil)))
    (expect (cl-cc/runtime::rt-functionp c) :to-equal 1)))

(it-sequential-each (("match" 42 integer 1)
                      ("no-match" "hi" integer 0))
    "rt-typep checks CL type by name (~A)."
    (label val type expected)
  (declare (ignore label))
  (expect (cl-cc/runtime::rt-typep val type) :to-equal expected))

(it-sequential
  "rt-type-of returns the CL type."
  (let ((ty (cl-cc/runtime::rt-type-of 42)))
    (expect (subtypep ty 'integer) :to-be-truthy)))
