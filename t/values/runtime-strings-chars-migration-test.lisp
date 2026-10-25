(in-package :cl-cc/runtime/values/test)

(it-sequential "rt-string-basic"
  (let ((s (cl-cc/runtime/values:rt-make-string 3 #\x)))
    (expect (= 3 (cl-cc/runtime/values:rt-string-length s)) :to-be-truthy)
    (expect (cl-cc/runtime/values:rt-string-ref s 0) :to-equal #\x)
    (cl-cc/runtime/values:rt-string-set s 1 #\y)
    (expect (cl-cc/runtime/values:rt-string-ref s 1) :to-equal #\y)))

(it-sequential "rt-string-comparisons =-t"
  (destructuring-bind (cmp-fn a b expected) (list #'cl-cc/runtime/values:rt-string= "abc" "abc" 1)
    (expect (= expected (funcall cmp-fn a b)) :to-be-truthy)))

(it-sequential "rt-string-comparisons =-f"
  (destructuring-bind (cmp-fn a b expected) (list #'cl-cc/runtime/values:rt-string= "abc" "abd" 0)
    (expect (= expected (funcall cmp-fn a b)) :to-be-truthy)))

(it-sequential "rt-string-comparisons <-t"
  (destructuring-bind (cmp-fn a b expected) (list #'cl-cc/runtime/values:rt-string< "abc" "abd" 1)
    (expect (= expected (funcall cmp-fn a b)) :to-be-truthy)))

(it-sequential "rt-string-comparisons <-f"
  (destructuring-bind (cmp-fn a b expected) (list #'cl-cc/runtime/values:rt-string< "abd" "abc" 0)
    (expect (= expected (funcall cmp-fn a b)) :to-be-truthy)))

(it-sequential "rt-string-comparisons >-t"
  (destructuring-bind (cmp-fn a b expected) (list #'cl-cc/runtime/values:rt-string> "abd" "abc" 1)
    (expect (= expected (funcall cmp-fn a b)) :to-be-truthy)))

(it-sequential "rt-string-comparisons >-f"
  (destructuring-bind (cmp-fn a b expected) (list #'cl-cc/runtime/values:rt-string> "abc" "abd" 0)
    (expect (= expected (funcall cmp-fn a b)) :to-be-truthy)))

(it-sequential "rt-string-comparison-extended <=-t"
  (destructuring-bind (cmp-fn a b expected) (list #'cl-cc/runtime/values:rt-string<= "abc" "abc" 1)
    (expect (= expected (funcall cmp-fn a b)) :to-be-truthy)))

(it-sequential "rt-string-comparison-extended <=-f"
  (destructuring-bind (cmp-fn a b expected) (list #'cl-cc/runtime/values:rt-string<= "abd" "abc" 0)
    (expect (= expected (funcall cmp-fn a b)) :to-be-truthy)))

(it-sequential "rt-string-comparison-extended >=-t"
  (destructuring-bind (cmp-fn a b expected) (list #'cl-cc/runtime/values:rt-string>= "abc" "abc" 1)
    (expect (= expected (funcall cmp-fn a b)) :to-be-truthy)))

(it-sequential "rt-string-comparison-extended >=-f"
  (destructuring-bind (cmp-fn a b expected) (list #'cl-cc/runtime/values:rt-string>= "abc" "abd" 0)
    (expect (= expected (funcall cmp-fn a b)) :to-be-truthy)))

(it-sequential "rt-string-comparison-extended ci-t"
  (destructuring-bind (cmp-fn a b expected) (list #'cl-cc/runtime/values:rt-string-equal-ci "ABC" "abc" 1)
    (expect (= expected (funcall cmp-fn a b)) :to-be-truthy)))

(it-sequential "rt-string-comparison-extended ci-f"
  (destructuring-bind (cmp-fn a b expected) (list #'cl-cc/runtime/values:rt-string-equal-ci "ABC" "xyz" 0)
    (expect (= expected (funcall cmp-fn a b)) :to-be-truthy)))

(it-sequential "rt-string-comparison-extended ne-t"
  (destructuring-bind (cmp-fn a b expected) (list #'cl-cc/runtime/values:rt-string-not-equal "abc" "xyz" 1)
    (expect (= expected (funcall cmp-fn a b)) :to-be-truthy)))

(it-sequential "rt-string-comparison-extended ne-f"
  (destructuring-bind (cmp-fn a b expected) (list #'cl-cc/runtime/values:rt-string-not-equal "abc" "abc" 0)
    (expect (= expected (funcall cmp-fn a b)) :to-be-truthy)))

(it-sequential "rt-string-comparison-extended lessp-t"
  (destructuring-bind (cmp-fn a b expected) (list #'cl-cc/runtime/values:rt-string-lessp "abc" "abd" 1)
    (expect (= expected (funcall cmp-fn a b)) :to-be-truthy)))

(it-sequential "rt-string-comparison-extended ngp-t"
  (destructuring-bind (cmp-fn a b expected) (list #'cl-cc/runtime/values:rt-string-not-greaterp "abc" "abc" 1)
    (expect (= expected (funcall cmp-fn a b)) :to-be-truthy)))

(it-sequential "rt-string-comparison-extended nlp-t"
  (destructuring-bind (cmp-fn a b expected) (list #'cl-cc/runtime/values:rt-string-not-lessp "abc" "abc" 1)
    (expect (= expected (funcall cmp-fn a b)) :to-be-truthy)))

(it-sequential "rt-string-transform-ops upcase"
  (destructuring-bind (fn input expected) (list #'cl-cc/runtime/values:rt-string-upcase "hello" "HELLO")
    (expect (funcall fn input) :to-equal expected)))

(it-sequential "rt-string-transform-ops downcase"
  (destructuring-bind (fn input expected) (list #'cl-cc/runtime/values:rt-string-downcase "HELLO" "hello")
    (expect (funcall fn input) :to-equal expected)))

(it-sequential "rt-string-transform-ops capitalize"
  (destructuring-bind (fn input expected) (list #'cl-cc/runtime/values:rt-string-capitalize "hello world" "Hello World")
    (expect (funcall fn input) :to-equal expected)))

(it-sequential "rt-string-transform-ops trim"
  (destructuring-bind (fn input expected) (list (lambda (s) (cl-cc/runtime/values:rt-string-trim " " s)) " hello " "hello")
    (expect (funcall fn input) :to-equal expected)))

(it-sequential "rt-string-transform-ops left-trim"
  (destructuring-bind (fn input expected) (list (lambda (s) (cl-cc/runtime/values:rt-string-left-trim " " s)) " hello " "hello ")
    (expect (funcall fn input) :to-equal expected)))

(it-sequential "rt-string-transform-ops right-trim"
  (destructuring-bind (fn input expected) (list (lambda (s) (cl-cc/runtime/values:rt-string-right-trim " " s)) " hello " " hello")
    (expect (funcall fn input) :to-equal expected)))

(it-sequential "rt-search-string-and-subseq"
  (expect (= 3 (cl-cc/runtime/values:rt-search-string "lo" "hello world")) :to-be-truthy)
  (expect (cl-cc/runtime/values:rt-subseq "hello" 2) :to-equal "llo"))

(it-sequential "rt-concatenate-seqs-string-and-list"
  (expect (cl-cc/runtime/values:rt-concatenate-seqs 'string "hello" " world") :to-equal "hello world")
  (expect (cl-cc/runtime/values:rt-concatenate-seqs 'list '(1 2) '(3 4)) :to-equal '(1 2 3 4)))

(it-sequential "rt-char-code-roundtrip"
  (expect (cl-cc/runtime/values:rt-code-char (cl-cc/runtime/values:rt-char-code #\A)) :to-equal #\A))

(it-sequential "rt-char-predicates alpha-t"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-alpha-char-p #\a 1)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-char-predicates alpha-f"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-alpha-char-p #\1 0)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-char-predicates digit-t"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-digit-char-p #\5 1)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-char-predicates digit-f"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-digit-char-p #\a 0)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-char-predicates alnum-t"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-alphanumericp #\a 1)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-char-predicates alnum-f"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-alphanumericp #\! 0)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-char-predicates upper-t"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-upper-case-p #\A 1)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-char-predicates upper-f"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-upper-case-p #\a 0)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-char-predicates lower-t"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-lower-case-p #\a 1)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-char-predicates lower-f"
  (destructuring-bind (pred-fn input expected) (list #'cl-cc/runtime/values:rt-lower-case-p #\A 0)
    (expect (= expected (funcall pred-fn input)) :to-be-truthy)))

(it-sequential "rt-char-case-ops upcase"
  (destructuring-bind (fn input expected) (list #'cl-cc/runtime/values:rt-char-upcase #\a #\A)
    (expect (funcall fn input) :to-equal expected)))

(it-sequential "rt-char-case-ops downcase"
  (destructuring-bind (fn input expected) (list #'cl-cc/runtime/values:rt-char-downcase #\A #\a)
    (expect (funcall fn input) :to-equal expected)))

(it-sequential "rt-char-comparisons-cs =-t"
  (destructuring-bind (fn a b expected) (list #'cl-cc/runtime/values:rt-char-equal-cs #\a #\a 1)
    (expect (= expected (funcall fn a b)) :to-be-truthy)))

(it-sequential "rt-char-comparisons-cs =-f"
  (destructuring-bind (fn a b expected) (list #'cl-cc/runtime/values:rt-char-equal-cs #\a #\b 0)
    (expect (= expected (funcall fn a b)) :to-be-truthy)))

(it-sequential "rt-char-comparisons-cs <-t"
  (destructuring-bind (fn a b expected) (list #'cl-cc/runtime/values:rt-char-lt-cs #\a #\b 1)
    (expect (= expected (funcall fn a b)) :to-be-truthy)))

(it-sequential "rt-char-comparisons-cs <-f"
  (destructuring-bind (fn a b expected) (list #'cl-cc/runtime/values:rt-char-lt-cs #\b #\a 0)
    (expect (= expected (funcall fn a b)) :to-be-truthy)))

(it-sequential "rt-char-comparisons-cs >-t"
  (destructuring-bind (fn a b expected) (list #'cl-cc/runtime/values:rt-char-gt-cs #\b #\a 1)
    (expect (= expected (funcall fn a b)) :to-be-truthy)))

(it-sequential "rt-char-comparisons-cs >-f"
  (destructuring-bind (fn a b expected) (list #'cl-cc/runtime/values:rt-char-gt-cs #\a #\b 0)
    (expect (= expected (funcall fn a b)) :to-be-truthy)))

(it-sequential "rt-char-comparisons-cs <=-t"
  (destructuring-bind (fn a b expected) (list #'cl-cc/runtime/values:rt-char-le-cs #\a #\a 1)
    (expect (= expected (funcall fn a b)) :to-be-truthy)))

(it-sequential "rt-char-comparisons-cs >=-t"
  (destructuring-bind (fn a b expected) (list #'cl-cc/runtime/values:rt-char-ge-cs #\a #\a 1)
    (expect (= expected (funcall fn a b)) :to-be-truthy)))

(it-sequential "rt-char-comparisons-cs ne-t"
  (destructuring-bind (fn a b expected) (list #'cl-cc/runtime/values:rt-char-ne-cs #\a #\b 1)
    (expect (= expected (funcall fn a b)) :to-be-truthy)))

(it-sequential "rt-char-comparisons-cs ne-f"
  (destructuring-bind (fn a b expected) (list #'cl-cc/runtime/values:rt-char-ne-cs #\a #\a 0)
    (expect (= expected (funcall fn a b)) :to-be-truthy)))

(it-sequential "rt-char-comparisons-ci equal-t"
  (destructuring-bind (fn a b expected) (list #'cl-cc/runtime/values:rt-char-equal-ci #\A #\a 1)
    (expect (= expected (funcall fn a b)) :to-be-truthy)))

(it-sequential "rt-char-comparisons-ci equal-f"
  (destructuring-bind (fn a b expected) (list #'cl-cc/runtime/values:rt-char-equal-ci #\A #\b 0)
    (expect (= expected (funcall fn a b)) :to-be-truthy)))

(it-sequential "rt-char-comparisons-ci ne-ci-t"
  (destructuring-bind (fn a b expected) (list #'cl-cc/runtime/values:rt-char-not-equal-ci #\a #\b 1)
    (expect (= expected (funcall fn a b)) :to-be-truthy)))

(it-sequential "rt-char-comparisons-ci lessp-t"
  (destructuring-bind (fn a b expected) (list #'cl-cc/runtime/values:rt-char-lessp-ci #\a #\B 1)
    (expect (= expected (funcall fn a b)) :to-be-truthy)))

(it-sequential "rt-char-comparisons-ci greaterp-t"
  (destructuring-bind (fn a b expected) (list #'cl-cc/runtime/values:rt-char-greaterp-ci #\B #\a 1)
    (expect (= expected (funcall fn a b)) :to-be-truthy)))

(it-sequential "rt-char-comparisons-ci nlessp-t"
  (destructuring-bind (fn a b expected) (list #'cl-cc/runtime/values:rt-char-not-lessp-ci #\A #\a 1)
    (expect (= expected (funcall fn a b)) :to-be-truthy)))

(it-sequential "rt-char-comparisons-ci ngreaterp-t"
  (destructuring-bind (fn a b expected) (list #'cl-cc/runtime/values:rt-char-not-greaterp-ci #\a #\A 1)
    (expect (= expected (funcall fn a b)) :to-be-truthy)))

(it-sequential "rt-char-name-and-digit"
  (expect (cl-cc/runtime/values:rt-char-name #\Space) :to-equal "Space")
  (expect (cl-cc/runtime/values:rt-digit-char 7) :to-equal #\7)
  (expect (cl-cc/runtime/values:rt-digit-char 10 16) :to-equal #\A))

(it-sequential "rt-parse-integer decimal"
  (destructuring-bind (input radix expected) (list "42" 10 42)
    (expect (= expected (cl-cc/runtime/values:rt-parse-integer input :radix radix)) :to-be-truthy)))

(it-sequential "rt-parse-integer hex"
  (destructuring-bind (input radix expected) (list "FF" 16 255)
    (expect (= expected (cl-cc/runtime/values:rt-parse-integer input :radix radix)) :to-be-truthy)))
