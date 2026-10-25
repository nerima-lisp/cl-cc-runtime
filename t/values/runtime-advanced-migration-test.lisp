(in-package :cl-cc/runtime/values/test)

(it-sequential "rt-bitwise-ops and"
  (destructuring-bind (fn a b expected) (list #'cl-cc/runtime/values:rt-logand #b1110 #b1011 #b1010)
    (expect (= expected (funcall fn a b)) :to-be-truthy)))

(it-sequential "rt-bitwise-ops or"
  (destructuring-bind (fn a b expected) (list #'cl-cc/runtime/values:rt-logior #b1010 #b0101 #b1111)
    (expect (= expected (funcall fn a b)) :to-be-truthy)))

(it-sequential "rt-bitwise-ops xor"
  (destructuring-bind (fn a b expected) (list #'cl-cc/runtime/values:rt-logxor #b1010 #b0101 #b1111)
    (expect (= expected (funcall fn a b)) :to-be-truthy)))

(it-sequential "rt-bitwise-ops ash-l"
  (destructuring-bind (fn a b expected) (list #'cl-cc/runtime/values:rt-ash 2 2 8)
    (expect (= expected (funcall fn a b)) :to-be-truthy)))

(it-sequential "rt-bitwise-ops ash-r"
  (destructuring-bind (fn a b expected) (list #'cl-cc/runtime/values:rt-ash 8 -2 2)
    (expect (= expected (funcall fn a b)) :to-be-truthy)))

(it-sequential "rt-bitwise-predicate-conventions logtest-overlap"
  (destructuring-bind (pred-fn a b expected) (list #'cl-cc/runtime/values:rt-logtest #b1010 #b1000 1)
    (expect (= expected (funcall pred-fn a b)) :to-be-truthy)))

(it-sequential "rt-bitwise-predicate-conventions logtest-disjoint"
  (destructuring-bind (pred-fn a b expected) (list #'cl-cc/runtime/values:rt-logtest #b1010 #b0101 0)
    (expect (= expected (funcall pred-fn a b)) :to-be-truthy)))

(it-sequential "rt-bitwise-predicate-conventions logbitp-set"
  (destructuring-bind (pred-fn a b expected) (list #'cl-cc/runtime/values:rt-logbitp 0 1 1)
    (expect (= expected (funcall pred-fn a b)) :to-be-truthy)))

(it-sequential "rt-bitwise-predicate-conventions logbitp-clear"
  (destructuring-bind (pred-fn a b expected) (list #'cl-cc/runtime/values:rt-logbitp 1 1 0)
    (expect (= expected (funcall pred-fn a b)) :to-be-truthy)))

(it-sequential "rt-symbol-name-returns-upcased-string"
  (expect (cl-cc/runtime/values:rt-symbol-name 'foo) :to-equal "FOO"))

(it-sequential "rt-gensym-returns-unique-symbols"
  (expect (eq (cl-cc/runtime/values:rt-gensym) (cl-cc/runtime/values:rt-gensym)) :to-be-falsy))

(it-sequential "rt-symbol-plist-roundtrip"
  (let ((sym (make-symbol "PLIST-TEST")))
    (cl-cc/runtime/values:rt-put-prop sym :color 'red)
    (expect (cl-cc/runtime/values:rt-get-prop sym :color) :to-be 'red)
    (cl-cc/runtime/values:rt-remprop sym :color)
    (expect (cl-cc/runtime/values:rt-get-prop sym :color) :to-be-falsy)))

(it-sequential "rt-intern-in-package"
  (let* ((pkg *package*)
         (sym (cl-cc/runtime/values:rt-intern "RT-INTERN-TEST-SYM" pkg))
         (sym2 (cl-cc/runtime/values:rt-intern "RT-INTERN-TEST-SYM" pkg)))
    (expect (symbolp sym) :to-be-truthy)
    (expect (symbol-name sym) :to-equal "RT-INTERN-TEST-SYM")
    (expect sym2 :to-be sym)))

(it-sequential "rt-hash-table-set-get-rem-count"
  (let ((ht (cl-cc/runtime/values:rt-make-hash-table)))
    (cl-cc/runtime/values:rt-sethash :a ht 1)
    (cl-cc/runtime/values:rt-sethash :b ht 2)
    (expect (= 1 (cl-cc/runtime/values:rt-gethash :a ht)) :to-be-truthy)
    (expect (= 2 (cl-cc/runtime/values:rt-hash-count ht)) :to-be-truthy)
    (cl-cc/runtime/values:rt-remhash :a ht)
    (expect (= 1 (cl-cc/runtime/values:rt-hash-count ht)) :to-be-truthy)))

(it-sequential "rt-hash-table-keys-values-clrhash"
  (let ((ht (cl-cc/runtime/values:rt-make-hash-table)))
    (cl-cc/runtime/values:rt-sethash :x ht 10)
    (cl-cc/runtime/values:rt-sethash :y ht 20)
    (expect (= 2 (length (cl-cc/runtime/values:rt-hash-keys ht))) :to-be-truthy)
    (expect (= 2 (length (cl-cc/runtime/values:rt-hash-values ht))) :to-be-truthy)
    (expect (member :x (cl-cc/runtime/values:rt-hash-keys ht)) :to-be-truthy)
    (expect (member 10 (cl-cc/runtime/values:rt-hash-values ht)) :to-be-truthy)
    (cl-cc/runtime/values:rt-clrhash ht)
    (expect (= 0 (cl-cc/runtime/values:rt-hash-count ht)) :to-be-truthy)))

(it-sequential "rt-maphash-and-hash-test"
  (let ((ht (cl-cc/runtime/values:rt-make-hash-table :test #'equal)))
    (cl-cc/runtime/values:rt-sethash "a" ht 1)
    (cl-cc/runtime/values:rt-sethash "b" ht 2)
    (let ((collected nil))
      (cl-cc/runtime/values:rt-maphash (lambda (k v) (push (cons k v) collected)) ht)
      (expect (= 2 (length collected)) :to-be-truthy))
    (expect (cl-cc/runtime/values:rt-hash-test ht) :to-equal 'equal)))

(it-sequential "rt-hash-table-resizing-accessors"
  (let ((ht (cl-cc/runtime/values:rt-make-hash-table :test #'equal
                                              :size 4
                                              :rehash-size 2.0
                                              :rehash-threshold 0.75))
        (weak (cl-cc/runtime/values:rt-make-hash-table :test #'equal
                                                :size 4
                                                :rehash-size 3.0
                                                :rehash-threshold 0.6
                                                :weakness :key)))
    (expect (cl-cc/runtime/values:rt-hash-test ht) :to-equal 'equal)
    (expect (>= (cl-cc/runtime/values:rt-hash-size ht) 4) :to-be-truthy)
    (expect (= 2.0 (cl-cc/runtime/values:rt-hash-rehash-size ht)) :to-be-truthy)
    (expect (= 0.75 (cl-cc/runtime/values:rt-hash-rehash-threshold ht)) :to-be-truthy)
    (expect (cl-cc/runtime/values:rt-hash-table-weakness weak) :to-equal :key)
    (expect (>= (cl-cc/runtime/values:rt-hash-size weak) 4) :to-be-truthy)
    (expect (= 3.0 (cl-cc/runtime/values:rt-hash-rehash-size weak)) :to-be-truthy)
    (expect (= 0.6 (cl-cc/runtime/values:rt-hash-rehash-threshold weak)) :to-be-truthy)))

(it-sequential "rt-fboundp-uses-runtime-function-registry"
  (let ((sym (gensym "RT-FBOUNDP-TEST-")))
    (expect (= 1 (cl-cc/runtime/values:rt-fboundp '+)) :to-be-truthy)
    (expect (= 0 (cl-cc/runtime/values:rt-fboundp sym)) :to-be-truthy)))

(it-sequential "rt-bootstrap-function-registry-uses-explicit-seed-list"
  (dolist (sym '(+ - * / 1+ 1- < > <= >= eql equal equalp char= char-equal
                 boundp makunbound fboundp fdefinition intern gensym symbol-value
                 make-string-output-stream get-output-stream-string write-string
                 write-to-string make-pathname merge-pathnames namestring
                 pathname-name pathname-type pathname-directory pathnamep probe-file
                 delete-file rename-file truename load make-broadcast-stream
                 make-concatenated-stream make-echo-stream))
    (expect (= 1 (cl-cc/runtime/values:rt-fboundp sym)) :to-be-truthy)))

(it-sequential "rt-package-registry-is-seeded-conservatively"
  (expect (cl-cc/runtime/values:rt-find-package :cl-cc/runtime) :to-be-truthy)
  (expect (cl-cc/runtime/values:rt-find-package :cl-cc/bootstrap) :to-be-truthy)
  (expect (cl-cc/runtime/values:rt-find-package :cl) :to-be-truthy)
  (expect (string= (cl-cc/runtime/values:rt-package-name
                    (cl-cc/runtime/values:rt-find-package :cl-cc/runtime))
                   "CL-CC/RUNTIME")
          :to-be-truthy))

(it-sequential "rt-intern-preserves-seeded-host-package-symbols"
  (let* ((pkg (cl-cc/runtime/values:rt-find-package :cl))
         (sym (cl-cc/runtime/values:rt-intern "CAR" pkg)))
    (expect sym :to-be 'cl:car)))

(it-sequential "rt-coerce-works"
  (expect (cl-cc/runtime/values:rt-coerce #(1 2 3) 'list) :to-equal '(1 2 3)))

(it-sequential "rt-read-from-string-roundtrip"
  (expect (= 42 (cl-cc/runtime/values:rt-read-from-string "42"))
          :to-be-truthy))

(it-sequential "rt-random-returns-in-range"
  (let ((r (cl-cc/runtime/values:rt-random 100)))
    (expect (integerp r) :to-be-truthy)
    (expect (and (>= r 0) (< r 100)) :to-be-truthy)))
