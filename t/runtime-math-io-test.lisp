;;;; t/runtime-math-io-test.lisp — Coverage for src/runtime-math-io.lisp
;;;;
;;;; Symbols, runtime special-variable binding stacks, scalar/sequence helpers,
;;;; hash tables (including weak-table metadata), and misc runtime primitives.
(in-package :cl-cc-runtime/test)

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
(it-sequential
  "rt-make-symbol returns a fresh uninterned symbol with the given name."
  (let ((s (cl-cc/runtime::rt-make-symbol "FOO")))
    (expect (symbolp s) :to-be-truthy)
    (expect (symbol-package s) :to-be-null)
    (expect (symbol-name s) :to-equal "FOO")))

(it-sequential
  "rt-put-prop / rt-get-prop / rt-remprop manage a symbol's plist."
  (let ((s (make-symbol "PROP-HOST")))
    (cl-cc/runtime::rt-put-prop s :color :red)
    (expect (cl-cc/runtime::rt-get-prop s :color) :to-be :red)
    (expect (member :color (cl-cc/runtime::rt-symbol-plist s)) :to-be-truthy)
    (cl-cc/runtime::rt-remprop s :color)
    (expect (cl-cc/runtime::rt-get-prop s :color) :to-be-null)))

;;; ------------------------------------------------------------
;;; Runtime special-variable registry and dynamic binding stacks
;;; ------------------------------------------------------------
(it-sequential
  "rt-set-symbol-value / rt-symbol-value use the runtime global registry."
  (with-fresh-var-registries
    (cl-cc/runtime::rt-set-symbol-value 'alpha 11)
    (expect (cl-cc/runtime::rt-symbol-value 'alpha) :to-equal 11)
    (expect (cl-cc/runtime::rt-boundp 'alpha) :to-equal 1)
    (cl-cc/runtime::rt-makunbound 'alpha)
    (expect (cl-cc/runtime::rt-boundp 'alpha) :to-equal 0)))

(it-sequential
  "rt-symbol-value signals when the variable was never assigned."
  (with-fresh-var-registries
    (signals error (cl-cc/runtime::rt-symbol-value 'no-such-runtime-var))))

(it-sequential
  "rt-dynamic-bind shadows the global value; rt-dynamic-unbind restores it."
  (with-fresh-var-registries
    (cl-cc/runtime::rt-set-symbol-value 'beta 1)
    (cl-cc/runtime::rt-dynamic-bind 'beta 2)
    (expect (cl-cc/runtime::rt-symbol-value 'beta) :to-equal 2)
    (cl-cc/runtime::rt-dynamic-unbind)
    (expect (cl-cc/runtime::rt-symbol-value 'beta) :to-equal 1)))

(it-sequential
  "rt-with-dynamic-binding installs and removes the binding around its body."
  (with-fresh-var-registries
    (cl-cc/runtime::rt-set-symbol-value 'gamma 10)
    (cl-cc/runtime::rt-with-dynamic-binding
      ('gamma 20)
      (expect (cl-cc/runtime::rt-symbol-value 'gamma) :to-equal 20))
    (expect (cl-cc/runtime::rt-symbol-value 'gamma) :to-equal 10)))

(it-sequential
  "rt-register-special-variable tracks global-only status until first bind."
  (with-fresh-var-registries
    (cl-cc/runtime::rt-register-special-variable 'delta :global-only-p t)
    (expect (cl-cc/runtime::rt-special-variable-global-only-p 'delta) :to-be-truthy)
    (cl-cc/runtime::rt-dynamic-bind 'delta 5)
    (expect (cl-cc/runtime::rt-special-variable-global-only-p 'delta) :to-be-falsy)))

;;; ------------------------------------------------------------
;;; Scalar / sequence helpers used by the VM bridge
;;; ------------------------------------------------------------
(it-sequential
  "rt-1+ / rt-1- adjust by one."
  (expect (cl-cc/runtime::rt-1+ 5) :to-equal 6)
  (expect (cl-cc/runtime::rt-1- 5) :to-equal 4))

(it-sequential
  "Variadic arithmetic helpers fold their arguments."
  (expect (cl-cc/runtime::rt-+ 1 2 3 4) :to-equal 10)
  (expect (cl-cc/runtime::rt-- 1 2 3 4) :to-equal -8)
  (expect (cl-cc/runtime::rt-* 1 2 3 4) :to-equal 24)
  (expect (cl-cc/runtime::rt-/ 16 2 2 2) :to-equal 2)
  (expect (cl-cc/runtime::rt-max 1 4 2) :to-equal 4)
  (expect (cl-cc/runtime::rt-min 1 4 2) :to-equal 1))

(it-sequential
  "Variadic comparison helpers apply the CL chained predicates."
  (expect (cl-cc/runtime::rt-< 1 2 3) :to-be-truthy)
  (expect (cl-cc/runtime::rt-> 3 2 1) :to-be-truthy)
  (expect (cl-cc/runtime::rt-<= 1 1 2) :to-be-truthy)
  (expect (cl-cc/runtime::rt->= 2 2 1) :to-be-truthy))

(it-sequential
  "rt-length / rt-elt / rt-append / rt-char= / rt-equalp match CL semantics."
  (expect (cl-cc/runtime::rt-length '(a b c)) :to-equal 3)
  (expect (cl-cc/runtime::rt-elt '(a b c) 1) :to-be 'b)
  (expect (cl-cc/runtime::rt-append '(1 2) '(3 4)) :to-equal '(1 2 3 4))
  (expect (cl-cc/runtime::rt-char= #\a #\a) :to-be-truthy)
  (expect (cl-cc/runtime::rt-char-equal #\a #\A) :to-be-truthy)
  (expect (cl-cc/runtime::rt-equalp "ABC" "abc") :to-be-truthy))

;;; ------------------------------------------------------------
;;; Hash tables
;;; ------------------------------------------------------------
(it-sequential
  "rt-make-hash-table plus accessors implement a full put/get/remove cycle."
  (let ((h (cl-cc/runtime::rt-make-hash-table :test #'equal)))
    (expect (cl-cc/runtime::rt-hash-table-p h) :to-equal 1)
    (expect (cl-cc/runtime::rt-hash-test h) :to-be 'equal)
    (cl-cc/runtime::rt-sethash "k" h 42)
    (expect (cl-cc/runtime::rt-gethash "k" h) :to-equal 42)
    (expect (cl-cc/runtime::rt-hash-count h) :to-equal 1)
    (cl-cc/runtime::rt-remhash "k" h)
    (expect (cl-cc/runtime::rt-hash-count h) :to-equal 0)))

(it-sequential
  "rt-maphash / rt-hash-keys / rt-hash-values / rt-clrhash traverse and reset."
  (let ((h (cl-cc/runtime::rt-make-hash-table :test #'eql)))
    (cl-cc/runtime::rt-sethash 1 h 10)
    (cl-cc/runtime::rt-sethash 2 h 20)
    (let ((sum 0))
      (cl-cc/runtime::rt-maphash
        (lambda (k v)
          (declare (ignore k))
          (incf sum v))
        h)
      (expect sum :to-equal 30))
    (expect (reduce #'+ (cl-cc/runtime::rt-hash-values h)) :to-equal 30)
    (expect (reduce #'+ (cl-cc/runtime::rt-hash-keys h)) :to-equal 3)
    (cl-cc/runtime::rt-clrhash h)
    (expect (cl-cc/runtime::rt-hash-count h) :to-equal 0)))

(it-sequential
  "Size / rehash accessors return positive numeric metadata."
  (let ((h (cl-cc/runtime::rt-make-hash-table :size 32)))
    (expect (>= (cl-cc/runtime::rt-hash-size h) 1) :to-be-truthy)
    (expect (plusp (cl-cc/runtime::rt-hash-rehash-size h)) :to-be-truthy)
    (expect (plusp (cl-cc/runtime::rt-hash-rehash-threshold h)) :to-be-truthy)))

(it-sequential
  "A weak hash table records its weakness mode and stores metadata entries."
  (let ((cl-cc/runtime::*rt-weak-hash-table-registry* nil))
    (let ((wh (cl-cc/runtime::rt-make-hash-table :test #'eq :weakness :key)))
      (expect (cl-cc/runtime::rt-weak-hash-table-p wh) :to-be-truthy)
      (expect (cl-cc/runtime::rt-hash-table-weakness wh) :to-be :key)
      (cl-cc/runtime::rt-sethash 'wk wh 7)
      (expect (cl-cc/runtime::rt-gethash 'wk wh) :to-equal 7)
      (expect (cl-cc/runtime::rt-hash-count wh) :to-equal 1)
      (cl-cc/runtime::rt-remhash 'wk wh)
      (expect (cl-cc/runtime::rt-hash-count wh) :to-equal 0))))

(it-sequential
  "An ordinary hash table reports NIL weakness."
  (let ((h (cl-cc/runtime::rt-make-hash-table)))
    (expect (cl-cc/runtime::rt-hash-table-weakness h) :to-be-null)))

(it-sequential
  "rt-make-hash-table rejects an unsupported weakness mode."
  (signals error (cl-cc/runtime::rt-make-hash-table :weakness :bogus)))

;;; ------------------------------------------------------------
;;; Misc primitives
;;; ------------------------------------------------------------
(it-sequential
  "rt-random returns a value within the requested bound."
  (let ((r (cl-cc/runtime::rt-random 10)))
    (expect (and (>= r 0) (< r 10)) :to-be-truthy))
  (expect
    (typep (cl-cc/runtime::rt-make-random-state) (quote random-state))
    :to-be-truthy))

(it-sequential
  "Runtime clock primitives return positive integers."
  (expect (integerp (cl-cc/runtime::rt-get-universal-time)) :to-be-truthy)
  (expect (integerp (cl-cc/runtime::rt-get-internal-real-time)) :to-be-truthy)
  (expect (integerp (cl-cc/runtime::rt-get-internal-run-time)) :to-be-truthy))

(it-sequential
  "rt-read-from-string / rt-read-sexp parse s-expressions."
  (expect (cl-cc/runtime::rt-read-from-string "(1 2 3)") :to-equal '(1 2 3))
  (with-input-from-string (s "(:a :b)")
    (expect (cl-cc/runtime::rt-read-sexp s) :to-equal '(:a :b))))

(it-sequential
  "rt-coerce delegates to CL coerce."
  (expect (cl-cc/runtime::rt-coerce 3 'double-float) :to-equal 3.0d0)
  (expect (cl-cc/runtime::rt-coerce '(1 2 3) 'vector) :to-equalp #(1 2 3)))
