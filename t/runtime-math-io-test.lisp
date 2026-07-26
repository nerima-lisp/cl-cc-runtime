;;;; t/runtime-math-io-test.lisp — Coverage for src/runtime-math-io.lisp
;;;;
;;;; Symbols, runtime special-variable binding stacks, scalar/sequence helpers,
;;;; hash tables (including weak-table metadata), and misc runtime primitives.

(in-package :cl-cc-runtime/test)

(in-suite cl-cc-unit-suite)

;;; Isolate the runtime special-variable registries so tests never leak
;;; bindings into each other or into the live runtime.
(defmacro with-fresh-var-registries (&body body)
  `(let ((cl-cc/runtime::*rt-global-var-registry* (make-hash-table :test #'eq))
         (cl-cc/runtime::*rt-special-variable-metadata* (make-hash-table :test #'eq))
         (cl-cc/runtime::*rt-dynamic-binding-stacks* (make-hash-table :test #'equal)))
     ,@body))

;;; ------------------------------------------------------------
;;; Symbols and property lists
;;; ------------------------------------------------------------

(deftest math-io-make-symbol-uninterned
  "rt-make-symbol returns a fresh uninterned symbol with the given name."
  (let ((s (cl-cc/runtime::rt-make-symbol "FOO")))
    (assert-true (symbolp s))
    (assert-null (symbol-package s))
    (assert-string= "FOO" (symbol-name s))))

(deftest math-io-property-list-ops
  "rt-put-prop / rt-get-prop / rt-remprop manage a symbol's plist."
  (let ((s (make-symbol "PROP-HOST")))
    (cl-cc/runtime::rt-put-prop s :color :red)
    (assert-eq :red (cl-cc/runtime::rt-get-prop s :color))
    (assert-true (member :color (cl-cc/runtime::rt-symbol-plist s)))
    (cl-cc/runtime::rt-remprop s :color)
    (assert-null (cl-cc/runtime::rt-get-prop s :color))))

;;; ------------------------------------------------------------
;;; Runtime special-variable registry and dynamic binding stacks
;;; ------------------------------------------------------------

(deftest math-io-symbol-value-global-registry
  "rt-set-symbol-value / rt-symbol-value use the runtime global registry."
  (with-fresh-var-registries
    (cl-cc/runtime::rt-set-symbol-value 'alpha 11)
    (assert-= 11 (cl-cc/runtime::rt-symbol-value 'alpha))
    (assert-= 1 (cl-cc/runtime::rt-boundp 'alpha))
    (cl-cc/runtime::rt-makunbound 'alpha)
    (assert-= 0 (cl-cc/runtime::rt-boundp 'alpha))))

(deftest math-io-symbol-value-unbound-errors
  "rt-symbol-value signals when the variable was never assigned."
  (with-fresh-var-registries
    (assert-signals error (cl-cc/runtime::rt-symbol-value 'no-such-runtime-var))))

(deftest math-io-dynamic-bind-shadows-global
  "rt-dynamic-bind shadows the global value; rt-dynamic-unbind restores it."
  (with-fresh-var-registries
    (cl-cc/runtime::rt-set-symbol-value 'beta 1)
    (cl-cc/runtime::rt-dynamic-bind 'beta 2)
    (assert-= 2 (cl-cc/runtime::rt-symbol-value 'beta))
    (cl-cc/runtime::rt-dynamic-unbind)
    (assert-= 1 (cl-cc/runtime::rt-symbol-value 'beta))))

(deftest math-io-with-dynamic-binding-macro
  "rt-with-dynamic-binding installs and removes the binding around its body."
  (with-fresh-var-registries
    (cl-cc/runtime::rt-set-symbol-value 'gamma 10)
    (cl-cc/runtime::rt-with-dynamic-binding ('gamma 20)
      (assert-= 20 (cl-cc/runtime::rt-symbol-value 'gamma)))
    (assert-= 10 (cl-cc/runtime::rt-symbol-value 'gamma))))

(deftest math-io-special-variable-metadata
  "rt-register-special-variable tracks global-only status until first bind."
  (with-fresh-var-registries
    (cl-cc/runtime::rt-register-special-variable 'delta :global-only-p t)
    (assert-true (cl-cc/runtime::rt-special-variable-global-only-p 'delta))
    (cl-cc/runtime::rt-dynamic-bind 'delta 5)
    (assert-false (cl-cc/runtime::rt-special-variable-global-only-p 'delta))))

;;; ------------------------------------------------------------
;;; Scalar / sequence helpers used by the VM bridge
;;; ------------------------------------------------------------

(deftest math-io-scalar-increment-helpers
  "rt-1+ / rt-1- adjust by one."
  (assert-= 6 (cl-cc/runtime::rt-1+ 5))
  (assert-= 4 (cl-cc/runtime::rt-1- 5)))

(deftest math-io-variadic-arithmetic
  "Variadic arithmetic helpers fold their arguments."
  (assert-= 10 (cl-cc/runtime::rt-+ 1 2 3 4))
  (assert-= -8 (cl-cc/runtime::rt-- 1 2 3 4))
  (assert-= 24 (cl-cc/runtime::rt-* 1 2 3 4))
  (assert-= 2 (cl-cc/runtime::rt-/ 16 2 2 2))
  (assert-= 4 (cl-cc/runtime::rt-max 1 4 2))
  (assert-= 1 (cl-cc/runtime::rt-min 1 4 2)))

(deftest math-io-variadic-comparisons
  "Variadic comparison helpers apply the CL chained predicates."
  (assert-true (cl-cc/runtime::rt-< 1 2 3))
  (assert-true (cl-cc/runtime::rt-> 3 2 1))
  (assert-true (cl-cc/runtime::rt-<= 1 1 2))
  (assert-true (cl-cc/runtime::rt->= 2 2 1)))

(deftest math-io-sequence-and-char-helpers
  "rt-length / rt-elt / rt-append / rt-char= / rt-equalp match CL semantics."
  (assert-= 3 (cl-cc/runtime::rt-length '(a b c)))
  (assert-eq 'b (cl-cc/runtime::rt-elt '(a b c) 1))
  (assert-equal '(1 2 3 4) (cl-cc/runtime::rt-append '(1 2) '(3 4)))
  (assert-true (cl-cc/runtime::rt-char= #\a #\a))
  (assert-true (cl-cc/runtime::rt-char-equal #\a #\A))
  (assert-true (cl-cc/runtime::rt-equalp "ABC" "abc")))

;;; ------------------------------------------------------------
;;; Hash tables
;;; ------------------------------------------------------------

(deftest math-io-hash-table-basic-lifecycle
  "rt-make-hash-table plus accessors implement a full put/get/remove cycle."
  (let ((h (cl-cc/runtime::rt-make-hash-table :test #'equal)))
    (assert-= 1 (cl-cc/runtime::rt-hash-table-p h))
    (assert-eq 'equal (cl-cc/runtime::rt-hash-test h))
    (cl-cc/runtime::rt-sethash "k" h 42)
    (assert-= 42 (cl-cc/runtime::rt-gethash "k" h))
    (assert-= 1 (cl-cc/runtime::rt-hash-count h))
    (cl-cc/runtime::rt-remhash "k" h)
    (assert-= 0 (cl-cc/runtime::rt-hash-count h))))

(deftest math-io-hash-table-clear-and-iterate
  "rt-maphash / rt-hash-keys / rt-hash-values / rt-clrhash traverse and reset."
  (let ((h (cl-cc/runtime::rt-make-hash-table :test #'eql)))
    (cl-cc/runtime::rt-sethash 1 h 10)
    (cl-cc/runtime::rt-sethash 2 h 20)
    (let ((sum 0))
      (cl-cc/runtime::rt-maphash (lambda (k v) (declare (ignore k)) (incf sum v)) h)
      (assert-= 30 sum))
    (assert-= 30 (reduce #'+ (cl-cc/runtime::rt-hash-values h)))
    (assert-= 3 (reduce #'+ (cl-cc/runtime::rt-hash-keys h)))
    (cl-cc/runtime::rt-clrhash h)
    (assert-= 0 (cl-cc/runtime::rt-hash-count h))))

(deftest math-io-hash-table-metadata-accessors
  "Size / rehash accessors return positive numeric metadata."
  (let ((h (cl-cc/runtime::rt-make-hash-table :size 32)))
    (assert-true (>= (cl-cc/runtime::rt-hash-size h) 1))
    (assert-true (plusp (cl-cc/runtime::rt-hash-rehash-size h)))
    (assert-true (plusp (cl-cc/runtime::rt-hash-rehash-threshold h)))))

(deftest math-io-weak-hash-table
  "A weak hash table records its weakness mode and stores metadata entries."
  (let ((cl-cc/runtime::*rt-weak-hash-table-registry* nil))
    (let ((wh (cl-cc/runtime::rt-make-hash-table :test #'eq :weakness :key)))
      (assert-true (cl-cc/runtime::rt-weak-hash-table-p wh))
      (assert-eq :key (cl-cc/runtime::rt-hash-table-weakness wh))
      (cl-cc/runtime::rt-sethash 'wk wh 7)
      (assert-= 7 (cl-cc/runtime::rt-gethash 'wk wh))
      (assert-= 1 (cl-cc/runtime::rt-hash-count wh))
      (cl-cc/runtime::rt-remhash 'wk wh)
      (assert-= 0 (cl-cc/runtime::rt-hash-count wh)))))

(deftest math-io-strong-hash-table-has-no-weakness
  "An ordinary hash table reports NIL weakness."
  (let ((h (cl-cc/runtime::rt-make-hash-table)))
    (assert-null (cl-cc/runtime::rt-hash-table-weakness h))))

(deftest math-io-invalid-weakness-signals
  "rt-make-hash-table rejects an unsupported weakness mode."
  (assert-signals error (cl-cc/runtime::rt-make-hash-table :weakness :bogus)))

;;; ------------------------------------------------------------
;;; Misc primitives
;;; ------------------------------------------------------------

(deftest math-io-random-in-range
  "rt-random returns a value within the requested bound."
  (let ((r (cl-cc/runtime::rt-random 10)))
    (assert-true (and (>= r 0) (< r 10))))
  (assert-type random-state (cl-cc/runtime::rt-make-random-state)))

(deftest math-io-time-primitives-are-positive-integers
  "Runtime clock primitives return positive integers."
  (assert-true (integerp (cl-cc/runtime::rt-get-universal-time)))
  (assert-true (integerp (cl-cc/runtime::rt-get-internal-real-time)))
  (assert-true (integerp (cl-cc/runtime::rt-get-internal-run-time))))

(deftest math-io-reader-helpers
  "rt-read-from-string / rt-read-sexp parse s-expressions."
  (assert-equal '(1 2 3) (cl-cc/runtime::rt-read-from-string "(1 2 3)"))
  (with-input-from-string (s "(:a :b)")
    (assert-equal '(:a :b) (cl-cc/runtime::rt-read-sexp s))))

(deftest math-io-coerce
  "rt-coerce delegates to CL coerce."
  (assert-= 3.0d0 (cl-cc/runtime::rt-coerce 3 'double-float))
  (assert-equalp #(1 2 3) (cl-cc/runtime::rt-coerce '(1 2 3) 'vector)))
