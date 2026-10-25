;;;; t/runtime-math-io-test.lisp — Coverage for src/runtime-math-io.lisp
;;;;
;;;; Symbols, runtime special-variable binding stacks, scalar/sequence helpers,
;;;; hash tables (including weak-table metadata), and misc runtime primitives.
(in-package :cl-cc/runtime/values/test)

;;; Isolate the runtime special-variable registries so tests never leak
;;; bindings into each other or into the live runtime.
;;; ------------------------------------------------------------
;;; Symbols and property lists
;;; ------------------------------------------------------------
(it-sequential
  "rt-put-prop / rt-get-prop / rt-remprop manage a symbol's plist."
  (let ((s (make-symbol "PROP-HOST")))
    (cl-cc/runtime/values:rt-put-prop s :color :red)
    (expect (cl-cc/runtime/values:rt-get-prop s :color) :to-be :red)
    (expect (member :color (cl-cc/runtime/values:rt-symbol-plist s)) :to-be-truthy)
    (cl-cc/runtime/values:rt-remprop s :color)
    (expect (cl-cc/runtime/values:rt-get-prop s :color) :to-be-null)))

;;; ------------------------------------------------------------
;;; Runtime special-variable registry and dynamic binding stacks
;;; ------------------------------------------------------------
;;; ------------------------------------------------------------
;;; Scalar / sequence helpers used by the VM bridge
;;; ------------------------------------------------------------
(it-sequential
  "rt-1+ / rt-1- adjust by one."
  (expect (cl-cc/runtime/values:rt-1+ 5) :to-equal 6)
  (expect (cl-cc/runtime/values:rt-1- 5) :to-equal 4))

(it-sequential
  "Variadic arithmetic helpers fold their arguments."
  (expect (cl-cc/runtime/values:rt-+ 1 2 3 4) :to-equal 10)
  (expect (cl-cc/runtime/values:rt-- 1 2 3 4) :to-equal -8)
  (expect (cl-cc/runtime/values:rt-* 1 2 3 4) :to-equal 24)
  (expect (cl-cc/runtime/values:rt-/ 16 2 2 2) :to-equal 2)
  (expect (cl-cc/runtime/values:rt-max 1 4 2) :to-equal 4)
  (expect (cl-cc/runtime/values:rt-min 1 4 2) :to-equal 1))

(it-sequential
  "Variadic comparison helpers apply the CL chained predicates."
  (expect (cl-cc/runtime/values:rt-< 1 2 3) :to-be-truthy)
  (expect (cl-cc/runtime/values:rt-> 3 2 1) :to-be-truthy)
  (expect (cl-cc/runtime/values:rt-<= 1 1 2) :to-be-truthy)
  (expect (cl-cc/runtime/values:rt->= 2 2 1) :to-be-truthy))

(it-sequential
  "rt-length / rt-elt / rt-append / rt-char= / rt-equalp match CL semantics."
  (expect (cl-cc/runtime/values:rt-length '(a b c)) :to-equal 3)
  (expect (cl-cc/runtime/values:rt-elt '(a b c) 1) :to-be 'b)
  (expect (cl-cc/runtime/values:rt-append '(1 2) '(3 4)) :to-equal '(1 2 3 4))
  (expect (cl-cc/runtime/values:rt-char= #\a #\a) :to-be-truthy)
  (expect (cl-cc/runtime/values:rt-char-equal #\a #\A) :to-be-truthy)
  (expect (cl-cc/runtime/values:rt-equalp "ABC" "abc") :to-be-truthy))

;;; ------------------------------------------------------------
;;; Hash tables
;;; ------------------------------------------------------------
(it-sequential
  "rt-make-hash-table plus accessors implement a full put/get/remove cycle."
  (let ((h (cl-cc/runtime/values:rt-make-hash-table :test #'equal)))
    (expect (cl-cc/runtime/values:rt-hash-table-p h) :to-equal 1)
    (expect (cl-cc/runtime/values:rt-hash-test h) :to-be 'equal)
    (cl-cc/runtime/values:rt-sethash "k" h 42)
    (expect (cl-cc/runtime/values:rt-gethash "k" h) :to-equal 42)
    (expect (cl-cc/runtime/values:rt-hash-count h) :to-equal 1)
    (cl-cc/runtime/values:rt-remhash "k" h)
    (expect (cl-cc/runtime/values:rt-hash-count h) :to-equal 0)))

(it-sequential
  "rt-maphash / rt-hash-keys / rt-hash-values / rt-clrhash traverse and reset."
  (let ((h (cl-cc/runtime/values:rt-make-hash-table :test #'eql)))
    (cl-cc/runtime/values:rt-sethash 1 h 10)
    (cl-cc/runtime/values:rt-sethash 2 h 20)
    (let ((sum 0))
      (cl-cc/runtime/values:rt-maphash
        (lambda (k v)
          (declare (ignore k))
          (incf sum v))
        h)
      (expect sum :to-equal 30))
    (expect (reduce #'+ (cl-cc/runtime/values:rt-hash-values h)) :to-equal 30)
    (expect (reduce #'+ (cl-cc/runtime/values:rt-hash-keys h)) :to-equal 3)
    (cl-cc/runtime/values:rt-clrhash h)
    (expect (cl-cc/runtime/values:rt-hash-count h) :to-equal 0)))

(it-sequential
  "Size / rehash accessors return positive numeric metadata."
  (let ((h (cl-cc/runtime/values:rt-make-hash-table :size 32)))
    (expect (>= (cl-cc/runtime/values:rt-hash-size h) 1) :to-be-truthy)
    (expect (plusp (cl-cc/runtime/values:rt-hash-rehash-size h)) :to-be-truthy)
    (expect (plusp (cl-cc/runtime/values:rt-hash-rehash-threshold h)) :to-be-truthy)))

;;; ------------------------------------------------------------
;;; Misc primitives
;;; ------------------------------------------------------------
(it-sequential
  "rt-random returns a value within the requested bound."
  (let ((r (cl-cc/runtime/values:rt-random 10)))
    (expect (and (>= r 0) (< r 10)) :to-be-truthy))
  (expect
    (typep (cl-cc/runtime/values:rt-make-random-state) (quote random-state))
    :to-be-truthy))

(it-sequential
  "rt-read-from-string / rt-read-sexp parse s-expressions."
  (expect (cl-cc/runtime/values:rt-read-from-string "(1 2 3)") :to-equal '(1 2 3))
  (with-input-from-string (s "(:a :b)")
    (expect (cl-cc/runtime/values:rt-read-sexp s) :to-equal '(:a :b))))

(it-sequential
  "rt-coerce delegates to CL coerce."
  (expect (cl-cc/runtime/values:rt-coerce 3 'double-float) :to-equal 3.0d0)
  (expect (cl-cc/runtime/values:rt-coerce '(1 2 3) 'vector) :to-equalp #(1 2 3)))

(in-package :cl-cc/runtime/values/test)

(it-sequential
  "rt-make-hash-table rejects an unsupported weakness mode."
  (signals error (cl-cc/runtime/values:rt-make-hash-table :weakness :bogus)))
