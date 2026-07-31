;;;; t/runtime-clos-test.lisp
;;;;
;;;; Tests for packages/runtime/src/runtime-clos.lisp:
;;;; rt-defclass, rt-register-method, rt-call-generic, *rt-primitive-type-classifiers*,
;;;; %rt-classify-arg, %rt-eql-specializer-p, %rt-extract-eql-specializer-keys,
;;;; rt-slot-value/set/boundp/makunbound/exists-p, rt-class-name, rt-class-of.
(in-package :cl-cc-runtime/test)

;;; ─── Helpers ────────────────────────────────────────────────────────────────
(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-class 'rt-clos-test-fixture nil)
    (defclass rt-clos-test-fixture ()
      ((x :initarg :x)))))

;;; ─── Class Descriptors ──────────────────────────────────────────────────────
(it-sequential
  "rt-defclass registers and returns a descriptor hash table with CPL metadata."
  (let ((cl-cc/runtime::*rt-class-registry* (make-hash-table :test #'eq)))
    (let ((base (cl-cc/runtime::rt-defclass 'rt-base '() '(x)))
          (child (cl-cc/runtime::rt-defclass 'rt-child '(rt-base) '(y))))
      (expect (hash-table-p base) :to-be-truthy)
      (expect (hash-table-p child) :to-be-truthy)
      (expect (cl-cc/runtime::rt-find-class 'rt-child) :to-be child)
      (expect (gethash :__name__ child) :to-be 'rt-child)
      (expect (member 'rt-base (gethash :__cpl__ child)) :to-be-truthy))))

(it-sequential
  "rt-register-method stores a method; rt-call-generic dispatches it."
  (let ((cl-cc/runtime::*rt-class-registry* (make-hash-table :test #'eq))
        (cl-cc/runtime::*rt-generic-function-registry* (make-hash-table :test #'equal)))
    (let* ((klass (cl-cc/runtime::rt-defclass 'rt-node '() '(value)))
           (obj (make-hash-table :test #'eq))
           (gf (make-hash-table :test #'equal)))
      (setf (gethash :__class__ obj) klass
            (gethash :__name__ gf) 'rt-describe)
      (cl-cc/runtime::rt-register-method
        gf
        'rt-node
        (lambda (instance)
          (gethash :__name__ (gethash :__class__ instance))))
      (expect (cl-cc/runtime::rt-call-generic gf obj) :to-be 'rt-node))))

(it-sequential
  "rt-compute-applicable-methods returns the registered primary descriptor."
  (let ((cl-cc/runtime::*rt-class-registry* (make-hash-table :test #'eq))
        (cl-cc/runtime::*rt-generic-function-registry* (make-hash-table :test #'equal)))
    (let* ((klass (cl-cc/runtime::rt-defclass 'rt-node '() '(value)))
           (obj (make-hash-table :test #'eq))
           (gf (make-hash-table :test #'equal)))
      (setf (gethash :__class__ obj) klass
            (gethash :__name__ gf) 'rt-describe)
      (cl-cc/runtime::rt-register-method
        gf
        'rt-node
        (lambda (instance)
          (gethash :__name__ (gethash :__class__ instance))))
      (let ((methods (cl-cc/runtime::rt-compute-applicable-methods gf (list obj))))
        (expect (length methods) :to-equal 1)
        (expect (gethash :specializer (first methods)) :to-be 'rt-node)
        (expect (functionp (gethash :function (first methods))) :to-be-truthy)))))

;;; ─── EQL Specializers ───────────────────────────────────────────────────────
(it-sequential-each (("eql-form" (eql 42) t)
                      ("non-eql"  (foo 42) nil)
                      ("not-cons" symbol   nil)
                      ("bare-eql" eql      nil))
    "%rt-eql-specializer-p recognizes (eql ...) lists only (~A)."
    (label form expected)
  (declare (ignore label))
  (expect (cl-cc/runtime::%rt-eql-specializer-p form) :to-equal expected))

(it-sequential-each (("direct"  (eql 42)   (42))
                      ("wrapped" ((eql 42)) (42))
                      ("non-eql" (integer)  nil)
                      ("symbol"  integer    nil))
    "%rt-extract-eql-specializer-keys extracts value from eql specializer forms (~A)."
    (label spec expected)
  (declare (ignore label))
  (expect
    (cl-cc/runtime::%rt-extract-eql-specializer-keys spec)
    :to-equal
    expected))

(it-sequential
  "rt-call-generic dispatches on eql specializers before class-based lookup."
  (let ((cl-cc/runtime::*rt-class-registry* (make-hash-table :test #'eq)))
    (let ((gf (make-hash-table :test #'equal)))
      (setf (gethash :__name__ gf) 'rt-eql-test-gf)
      (cl-cc/runtime::rt-register-method
        gf
        '(eql 99)
        (lambda (x)
          (* x 2)))
      (expect (hash-table-count (gethash :__eql-index__ gf)) :to-equal 1)
      (expect (cl-cc/runtime::rt-call-generic gf 99) :to-equal 198))))

(it-sequential
  "rt-call-generic uses the EQL index before class fallback methods."
  (let ((gf (make-hash-table :test #'equal)))
    (setf (gethash :__name__ gf) 'rt-eql-fallback-test-gf)
    (cl-cc/runtime::rt-register-method
      gf
      'symbol
      (lambda (x)
        (declare (ignore x))
        :class))
    (cl-cc/runtime::rt-register-method
      gf
      '(eql :read)
      (lambda (x)
        (declare (ignore x))
        :eql))
    (expect (cl-cc/runtime::rt-call-generic gf :read) :to-be :eql)
    (expect (cl-cc/runtime::rt-call-generic gf :write) :to-be :class)))

(it-sequential
  "rt-call-generic executes before -> primary -> after (after in reverse order)."
  (let ((cl-cc/runtime::*rt-class-registry* (make-hash-table :test #'eq)))
    (let* ((klass (cl-cc/runtime::rt-defclass 'rt-combo-node '() '()))
           (obj (make-hash-table :test #'eq))
           (log '())
           (gf (make-hash-table :test #'equal)))
      (setf (gethash :__class__ obj) klass
            (gethash :__name__ gf) 'rt-combo)
      (cl-cc/runtime::rt-register-method
        gf
        '(:__BEFORE__ rt-combo-node)
        (lambda (_)
          (declare (ignore _))
          (push :before log)))
      (cl-cc/runtime::rt-register-method
        gf
        'rt-combo-node
        (lambda (_)
          (declare (ignore _))
          (push :primary log)
          :ok))
      (cl-cc/runtime::rt-register-method
        gf
        '(:__AFTER__ rt-combo-node)
        (lambda (_)
          (declare (ignore _))
          (push :after-1 log)))
      (cl-cc/runtime::rt-register-method
        gf
        '(:__AFTER__ t)
        (lambda (_)
          (declare (ignore _))
          (push :after-2 log)))
      (expect (cl-cc/runtime::rt-call-generic gf obj) :to-be :ok)
      (expect log :to-equal '(:after-1 :after-2 :primary :before)))))

(it-sequential
  "rt-call-generic folds qualified methods using custom method-combination operator."
  (let ((cl-cc/runtime::*rt-class-registry* (make-hash-table :test #'eq)))
    (let* ((klass (cl-cc/runtime::rt-defclass 'rt-sum-node '() '()))
           (obj (make-hash-table :test #'eq))
           (gf (make-hash-table :test #'equal)))
      (setf (gethash :__class__ obj) klass
            (gethash :__name__ gf) 'rt-sum
            (gethash :__method-combination__ gf) '+)
      (cl-cc/runtime::rt-register-method
        gf
        '(:__+__ rt-sum-node)
        (lambda (_)
          (declare (ignore _))
          10))
      (cl-cc/runtime::rt-register-method
        gf
        '(:__+__ t)
        (lambda (_)
          (declare (ignore _))
          7))
      (expect (cl-cc/runtime::rt-call-generic gf obj) :to-equal 17))))

(it-sequential
  "rt-register-method accepts optional qualifier and stores qualified method key."
  (let ((gf (make-hash-table :test #'equal)))
    (setf (gethash :__methods__ gf) (make-hash-table :test #'equal)
          (gethash :__eql-index__ gf) (make-hash-table :test #'equal))
    (cl-cc/runtime::rt-register-method
      gf
      'my-class
      (lambda (x)
        x)
      :before)
    (expect
      (functionp (gethash '(:__BEFORE__ my-class) (gethash :__methods__ gf)))
      :to-be-truthy)))

;;; ─── Argument Classification ────────────────────────────────────────────────
(it-sequential-each (("integer" 42       integer)
                      ("string"  "hello"  string)
                      ("symbol"  foo      symbol)
                      ("unknown" 3.14     t)
                      ("vector"  #(1 2 3) t))
    "*rt-primitive-type-classifiers* drives %rt-classify-arg for CL primitive values (~A)."
    (label arg expected)
  (declare (ignore label))
  (expect (cl-cc/runtime::%rt-classify-arg arg) :to-equal expected))

(it-sequential
  "%rt-classify-arg extracts :__name__ from a descriptor hash table."
  (let* ((class-ht (make-hash-table :test #'eq))
         (obj (make-hash-table :test #'eq)))
    (setf (gethash :__name__ class-ht) 'my-class
          (gethash :__class__ obj) class-ht)
    (expect (cl-cc/runtime::%rt-classify-arg obj) :to-be 'my-class)))

(it-sequential
  "%rt-classify-arg returns T for a hash table without :__class__."
  (let ((ht (make-hash-table :test #'eq)))
    (expect (cl-cc/runtime::%rt-classify-arg ht) :to-be t)))

(it-sequential
  "*rt-primitive-type-classifiers* contains exactly integer/string/symbol."
  (let ((table cl-cc/runtime::*rt-primitive-type-classifiers*))
    (expect (assoc 'integer table) :to-be-truthy)
    (expect (assoc 'string table) :to-be-truthy)
    (expect (assoc 'symbol table) :to-be-truthy)
    (expect (length table) :to-equal 3)))

;;; ─── Slot Access ────────────────────────────────────────────────────────────
(it-sequential
  "rt-slot-value/set/boundp/makunbound/exists-p on standard CLOS instances."
  (let ((obj (make-instance 'rt-clos-test-fixture :x 42)))
    (expect (cl-cc/runtime::rt-slot-value obj 'x) :to-equal 42)
    (cl-cc/runtime::rt-slot-set obj 'x 99)
    (expect (cl-cc/runtime::rt-slot-value obj 'x) :to-equal 99)
    (expect (cl-cc/runtime::rt-slot-boundp obj 'x) :to-equal 1)
    (expect (cl-cc/runtime::rt-slot-exists-p obj 'x) :to-equal 1)
    (expect (cl-cc/runtime::rt-slot-exists-p obj 'nonexistent) :to-equal 0)
    (cl-cc/runtime::rt-slot-makunbound obj 'x)
    (expect (cl-cc/runtime::rt-slot-boundp obj 'x) :to-equal 0)))

(it-sequential
  "rt-class-name/rt-class-of work on hash-table descriptors and real CLOS objects."
  (let ((ht (make-hash-table :test #'eq)))
    (setf (gethash :__name__ ht) 'my-class)
    (expect (cl-cc/runtime::rt-class-name ht) :to-be 'my-class))
  (let ((obj (make-instance 'rt-clos-test-fixture :x 1)))
    (expect
      (class-name (cl-cc/runtime::rt-class-of obj))
      :to-be
      'rt-clos-test-fixture)))

;;; ─── %rt-cpl-walk (extracted helper) ────────────────────────────────────────
(it-sequential
  "%rt-cpl-walk: passing NAME already in SEEN returns SEEN unchanged."
  (let ((cl-cc/runtime::*rt-class-registry* (make-hash-table :test #'eq)))
    (expect (cl-cc/runtime::%rt-cpl-walk 'foo '(foo)) :to-equal '(foo))))

(it-sequential
  "%rt-cpl-walk on a class with no superclasses returns (name)."
  (let ((cl-cc/runtime::*rt-class-registry* (make-hash-table :test #'eq)))
    (cl-cc/runtime::rt-defclass 'cpl-base '() '())
    (expect (cl-cc/runtime::%rt-cpl-walk 'cpl-base '()) :to-equal '(cpl-base))))

(it-sequential
  "%rt-cpl-walk on child→parent returns (child parent) in order."
  (let ((cl-cc/runtime::*rt-class-registry* (make-hash-table :test #'eq)))
    (cl-cc/runtime::rt-defclass 'cpl-parent '() '())
    (cl-cc/runtime::rt-defclass 'cpl-child '(cpl-parent) '())
    (let ((result (cl-cc/runtime::%rt-cpl-walk 'cpl-child '())))
      (expect (member 'cpl-child result :test #'eq) :to-be-truthy)
      (expect (member 'cpl-parent result :test #'eq) :to-be-truthy)
      (expect
        (< (position 'cpl-child result) (position 'cpl-parent result))
        :to-be-truthy))))
