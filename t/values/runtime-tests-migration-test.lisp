(in-package :cl-cc/runtime/values/test)

(it-sequential "rt-tag-fixnum zero"
  (destructuring-bind (n expected) (list 0 0)
    (expect (= expected (cl-cc/runtime/values:rt-tag-fixnum n)) :to-be-truthy)))

(it-sequential "rt-tag-fixnum one"
  (destructuring-bind (n expected) (list 1 8)
    (expect (= expected (cl-cc/runtime/values:rt-tag-fixnum n)) :to-be-truthy)))

(it-sequential "rt-tag-fixnum forty-two"
  (destructuring-bind (n expected) (list 42 336)
    (expect (= expected (cl-cc/runtime/values:rt-tag-fixnum n)) :to-be-truthy)))

(it-sequential "rt-untag-fixnum-roundtrip"
  (dolist (n '(0 1 42 -7 1000000))
    (expect (= n (cl-cc/runtime/values:rt-untag-fixnum (cl-cc/runtime/values:rt-tag-fixnum n))) :to-be-truthy)))

(it-sequential "rt-tag-bits-extracts-low-3 fixnum-8"
  (destructuring-bind (tagged expected-bits) (list 8 0)
    (expect (= expected-bits (cl-cc/runtime/values:rt-tag-bits tagged)) :to-be-truthy)))

(it-sequential "rt-tag-bits-extracts-low-3 cons-9"
  (destructuring-bind (tagged expected-bits) (list 9 1)
    (expect (= expected-bits (cl-cc/runtime/values:rt-tag-bits tagged)) :to-be-truthy)))

(it-sequential "rt-tag-bits-extracts-low-3 max-15"
  (destructuring-bind (tagged expected-bits) (list 15 7)
    (expect (= expected-bits (cl-cc/runtime/values:rt-tag-bits tagged)) :to-be-truthy)))

(it-sequential "rt-tag-bits-extracts-low-3 plain-5"
  (destructuring-bind (tagged expected-bits) (list 5 5)
    (expect (= expected-bits (cl-cc/runtime/values:rt-tag-bits tagged)) :to-be-truthy)))

(it-sequential "rt-tag-constants-distinct"
  (let ((tags (list cl-cc/runtime/values:+tag-fixnum+
                    cl-cc/runtime/values:+rt-tag-cons+
                    cl-cc/runtime/values:+rt-tag-symbol+
                    cl-cc/runtime/values:+rt-tag-function+
                    cl-cc/runtime/values:+tag-character+
                    cl-cc/runtime/values:+tag-array+
                    cl-cc/runtime/values:+rt-tag-string+
                    cl-cc/runtime/values:+tag-other+)))
    (expect (= 8 (length (remove-duplicates tags))) :to-be-truthy)
    (dolist (tag tags) (expect (and (>= tag 0) (<= tag 7)) :to-be-truthy))))

(it-sequential "rt-values-buffer-push-ops"
  (cl-cc/runtime/values:rt-values-clear)
  (expect (= 0 (cl-cc/runtime/values:rt-values-count)) :to-be-truthy)
  (cl-cc/runtime/values:rt-values-push 10)
  (cl-cc/runtime/values:rt-values-push 20)
  (expect (= 2 (cl-cc/runtime/values:rt-values-count)) :to-be-truthy))

(it-sequential "rt-values-buffer-ref"
  (cl-cc/runtime/values:rt-values-clear)
  (cl-cc/runtime/values:rt-values-push :a)
  (cl-cc/runtime/values:rt-values-push :b)
  (cl-cc/runtime/values:rt-values-push :c)
  (expect (cl-cc/runtime/values:rt-values-ref 0) :to-be :a)
  (expect (cl-cc/runtime/values:rt-values-ref 1) :to-be :b)
  (expect (cl-cc/runtime/values:rt-values-ref 2) :to-be :c))

(it-sequential "rt-values-buffer-to-list"
  (cl-cc/runtime/values:rt-values-clear)
  (cl-cc/runtime/values:rt-values-push 1)
  (cl-cc/runtime/values:rt-values-push 2)
  (expect (cl-cc/runtime/values:rt-values-to-list) :to-equal '(1 2)))

(it-sequential "rt-spread-values-shapes list"
  (destructuring-bind (input expected-count expected-first) (list '(10 20 30) 3 10)
    (cl-cc/runtime/values:rt-values-clear) (cl-cc/runtime/values:rt-spread-values input) (expect (= expected-count (cl-cc/runtime/values:rt-values-count)) :to-be-truthy) (expect (= expected-first (cl-cc/runtime/values:rt-values-ref 0)) :to-be-truthy)))

(it-sequential "rt-spread-values-shapes atom"
  (destructuring-bind (input expected-count expected-first) (list 42 1 42)
    (cl-cc/runtime/values:rt-values-clear) (cl-cc/runtime/values:rt-spread-values input) (expect (= expected-count (cl-cc/runtime/values:rt-values-count)) :to-be-truthy) (expect (= expected-first (cl-cc/runtime/values:rt-values-ref 0)) :to-be-truthy)))

(it-sequential "rt-ensure-values-behavior empty"
  (destructuring-bind (pre-val ensure-val expected-count expected-ref0) (list nil 99 1 99)
    (cl-cc/runtime/values:rt-values-clear) (when pre-val (cl-cc/runtime/values:rt-values-push pre-val)) (cl-cc/runtime/values:rt-ensure-values ensure-val) (expect (= expected-count (cl-cc/runtime/values:rt-values-count)) :to-be-truthy) (expect (= expected-ref0 (cl-cc/runtime/values:rt-values-ref 0)) :to-be-truthy)))

(it-sequential "rt-ensure-values-behavior non-empty"
  (destructuring-bind (pre-val ensure-val expected-count expected-ref0) (list 1 99 1 1)
    (cl-cc/runtime/values:rt-values-clear) (when pre-val (cl-cc/runtime/values:rt-values-push pre-val)) (cl-cc/runtime/values:rt-ensure-values ensure-val) (expect (= expected-count (cl-cc/runtime/values:rt-values-count)) :to-be-truthy) (expect (= expected-ref0 (cl-cc/runtime/values:rt-values-ref 0)) :to-be-truthy)))

(it-sequential "rt-type-predicates consp-t"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-consp '(1 . 2) 1)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-type-predicates consp-f"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-consp 42 0)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-type-predicates null-p-t"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-null-p nil 1)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-type-predicates null-p-f"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-null-p 42 0)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-type-predicates symbolp-t"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-symbolp 'foo 1)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-type-predicates symbolp-f"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-symbolp 42 0)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-type-predicates numberp-t"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-numberp 3.14 1)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-type-predicates numberp-f"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-numberp "hi" 0)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-type-predicates integerp-t"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-integerp 42 1)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-type-predicates integerp-f"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-integerp 3.14 0)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-type-predicates floatp-t"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-floatp 1.0 1)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-type-predicates floatp-f"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-floatp 1 0)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-type-predicates stringp-t"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-stringp "hi" 1)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-type-predicates stringp-f"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-stringp 42 0)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-type-predicates characterp-t"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-characterp #\a 1)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-type-predicates characterp-f"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-characterp 42 0)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-type-predicates vectorp-t"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-vectorp #(1 2) 1)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-type-predicates vectorp-f"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-vectorp 42 0)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-type-predicates listp-t"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-listp '(1) 1)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-type-predicates listp-nil"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-listp nil 1)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-type-predicates listp-f"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-listp 42 0)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-type-predicates atomp-t"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-atomp 42 1)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-type-predicates atomp-f"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-atomp '(1) 0)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-type-predicates keywordp-t"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-keywordp :foo 1)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-type-predicates keywordp-f"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-keywordp 'foo 0)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-type-predicates hash-t"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-hash-table-p (make-hash-table) 1)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-type-predicates hash-f"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-hash-table-p 42 0)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-typep-integer match"
  (destructuring-bind (val type expected) (list 42 'integer 1)
    (expect (= expected (cl-cc/runtime/values:rt-typep val type)) :to-be-truthy)))

(it-sequential "rt-typep-integer no-match"
  (destructuring-bind (val type expected) (list "hi" 'integer 0)
    (expect (= expected (cl-cc/runtime/values:rt-typep val type)) :to-be-truthy)))

(it-sequential "rt-type-of-integer"
  (let ((ty (cl-cc/runtime/values:rt-type-of 42)))
    (expect (subtypep ty 'integer) :to-be-truthy)))
