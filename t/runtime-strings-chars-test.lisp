;;;; t/runtime-strings-chars-test.lisp
;;;;
;;;; Tests for packages/runtime/src/runtime-strings.lisp:
;;;; string ops, string comparisons, char ops, char comparisons, char predicates.
(in-package :cl-cc-runtime/test)

;;; ─── String Operations ─────────────────────────────────────────────────────
(it-sequential
  "rt-make-string, rt-string-length, rt-string-ref, rt-string-set."
  (let ((s (cl-cc/runtime::rt-make-string 3 #\x)))
    (expect (cl-cc/runtime::rt-string-length s) :to-equal 3)
    (expect (cl-cc/runtime::rt-string-ref s 0) :to-equal #\x)
    (cl-cc/runtime::rt-string-set s 1 #\y)
    (expect (cl-cc/runtime::rt-string-ref s 1) :to-equal #\y)))

(it-sequential-each (("=-t" cl-cc/runtime::rt-string= "abc" "abc" 1)
                      ("=-f" cl-cc/runtime::rt-string= "abc" "abd" 0)
                      ("<-t" cl-cc/runtime::rt-string< "abc" "abd" 1)
                      ("<-f" cl-cc/runtime::rt-string< "abd" "abc" 0)
                      (">-t" cl-cc/runtime::rt-string> "abd" "abc" 1)
                      (">-f" cl-cc/runtime::rt-string> "abc" "abd" 0))
    "String comparison wrappers return 1/0 (~A)."
    (label cmp-fn a b expected)
  (declare (ignore label))
  (expect (funcall cmp-fn a b) :to-equal expected))

(it-sequential-each (("<=-t" cl-cc/runtime::rt-string<= "abc" "abc" 1)
                      ("<=-f" cl-cc/runtime::rt-string<= "abd" "abc" 0)
                      (">=-t" cl-cc/runtime::rt-string>= "abc" "abc" 1)
                      (">=-f" cl-cc/runtime::rt-string>= "abc" "abd" 0)
                      ("ci-t" cl-cc/runtime::rt-string-equal-ci "ABC" "abc" 1)
                      ("ci-f" cl-cc/runtime::rt-string-equal-ci "ABC" "xyz" 0)
                      ("ne-t" cl-cc/runtime::rt-string-not-equal "abc" "xyz" 1)
                      ("ne-f" cl-cc/runtime::rt-string-not-equal "abc" "abc" 0)
                      ("lessp-t" cl-cc/runtime::rt-string-lessp "abc" "abd" 1)
                      ("ngp-t" cl-cc/runtime::rt-string-not-greaterp "abc" "abc" 1)
                      ("nlp-t" cl-cc/runtime::rt-string-not-lessp "abc" "abc" 1))
    "String comparison wrappers: <=, >=, case-insensitive, not-equal variants (~A)."
    (label cmp-fn a b expected)
  (declare (ignore label))
  (expect (funcall cmp-fn a b) :to-equal expected))

(it-sequential-each (("upcase" :fn cl-cc/runtime::rt-string-upcase "hello" "HELLO")
                      ("downcase" :fn cl-cc/runtime::rt-string-downcase "HELLO" "hello")
                      ("capitalize" :fn cl-cc/runtime::rt-string-capitalize "hello world" "Hello World")
                      ("trim" :trim nil " hello " "hello")
                      ("left-trim" :left-trim nil " hello " "hello ")
                      ("right-trim" :right-trim nil " hello " " hello"))
    "String case and trim operations produce correct output (~A)."
    (label kind fn input expected)
  (declare (ignore label))
  (let ((result (case kind
                  (:trim (cl-cc/runtime::rt-string-trim " " input))
                  (:left-trim (cl-cc/runtime::rt-string-left-trim " " input))
                  (:right-trim (cl-cc/runtime::rt-string-right-trim " " input))
                  (:fn (funcall fn input)))))
    (expect result :to-equal expected)))

(it-sequential
  "rt-search-string and rt-subseq."
  (expect (cl-cc/runtime::rt-search-string "lo" "hello world") :to-equal 3)
  (expect (cl-cc/runtime::rt-subseq "hello" 2) :to-equal "llo"))

(it-sequential
  "rt-concatenate-seqs joins strings and lists."
  (expect
    (cl-cc/runtime::rt-concatenate-seqs 'string "hello" " world")
    :to-equal
    "hello world")
  (expect
    (cl-cc/runtime::rt-concatenate-seqs 'list '(1 2) '(3 4))
    :to-equal
    '(1 2 3 4)))

;;; ─── Character Operations ──────────────────────────────────────────────────
(it-sequential
  "rt-char-code and rt-code-char roundtrip."
  (expect
    (cl-cc/runtime::rt-code-char (cl-cc/runtime::rt-char-code #\A))
    :to-equal
    #\A))

(it-sequential-each (("alpha-t" cl-cc/runtime::rt-alpha-char-p #\a 1)
                      ("alpha-f" cl-cc/runtime::rt-alpha-char-p #\1 0)
                      ("digit-t" cl-cc/runtime::rt-digit-char-p #\5 1)
                      ("digit-f" cl-cc/runtime::rt-digit-char-p #\a 0)
                      ("alnum-t" cl-cc/runtime::rt-alphanumericp #\a 1)
                      ("alnum-f" cl-cc/runtime::rt-alphanumericp #\! 0)
                      ("upper-t" cl-cc/runtime::rt-upper-case-p #\A 1)
                      ("upper-f" cl-cc/runtime::rt-upper-case-p #\a 0)
                      ("lower-t" cl-cc/runtime::rt-lower-case-p #\a 1)
                      ("lower-f" cl-cc/runtime::rt-lower-case-p #\A 0))
    "Character predicates return 1/0 (~A)."
    (label pred-fn input expected)
  (declare (ignore label))
  (expect (funcall pred-fn input) :to-equal expected))

(it-sequential-each (("upcase" cl-cc/runtime::rt-char-upcase #\a #\A)
                      ("downcase" cl-cc/runtime::rt-char-downcase #\A #\a))
    "rt-char-upcase/downcase: convert character case (~A)."
    (label fn input expected)
  (declare (ignore label))
  (expect (funcall fn input) :to-equal expected))

(it-sequential-each (("=-t" cl-cc/runtime::rt-char-equal-cs #\a #\a 1)
                      ("=-f" cl-cc/runtime::rt-char-equal-cs #\a #\b 0)
                      ("<-t" cl-cc/runtime::rt-char-lt-cs #\a #\b 1)
                      ("<-f" cl-cc/runtime::rt-char-lt-cs #\b #\a 0)
                      (">-t" cl-cc/runtime::rt-char-gt-cs #\b #\a 1)
                      (">-f" cl-cc/runtime::rt-char-gt-cs #\a #\b 0)
                      ("<=-t" cl-cc/runtime::rt-char-le-cs #\a #\a 1)
                      (">=-t" cl-cc/runtime::rt-char-ge-cs #\a #\a 1)
                      ("ne-t" cl-cc/runtime::rt-char-ne-cs #\a #\b 1)
                      ("ne-f" cl-cc/runtime::rt-char-ne-cs #\a #\a 0))
    "Case-sensitive char comparison wrappers return 1/0 (~A)."
    (label fn a b expected)
  (declare (ignore label))
  (expect (funcall fn a b) :to-equal expected))

(it-sequential-each (("equal-t" cl-cc/runtime::rt-char-equal-ci #\A #\a 1)
                      ("equal-f" cl-cc/runtime::rt-char-equal-ci #\A #\b 0)
                      ("ne-ci-t" cl-cc/runtime::rt-char-not-equal-ci #\a #\b 1)
                      ("lessp-t" cl-cc/runtime::rt-char-lessp-ci #\a #\B 1)
                      ("greaterp-t" cl-cc/runtime::rt-char-greaterp-ci #\B #\a 1)
                      ("nlessp-t" cl-cc/runtime::rt-char-not-lessp-ci #\A #\a 1)
                      ("ngreaterp-t" cl-cc/runtime::rt-char-not-greaterp-ci #\a #\A 1))
    "Case-insensitive char comparison wrappers return 1/0 (~A)."
    (label fn a b expected)
  (declare (ignore label))
  (expect (funcall fn a b) :to-equal expected))

(it-sequential
  "rt-char-name names special chars; rt-digit-char reverses digit lookup."
  (expect (cl-cc/runtime::rt-char-name #\Space) :to-equal "Space")
  (expect (cl-cc/runtime::rt-digit-char 7) :to-equal #\7)
  (expect (cl-cc/runtime::rt-digit-char 10 16) :to-equal #\A))

(it-sequential-each (("decimal" "42" 10 42)
                      ("hex" "FF" 16 255))
    "rt-parse-integer: decimal and hex (with :radix) parsing (~A)."
    (label input radix expected)
  (declare (ignore label))
  (expect (cl-cc/runtime::rt-parse-integer input :radix radix) :to-equal expected))
