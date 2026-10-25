(in-package :cl-cc/runtime/clos/test)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-class 'rt-clos-test-fixture nil)
    (defclass rt-clos-test-fixture () ((x :initarg :x)))))

(it-sequential "rt-defclass-registers-descriptor"
  (let ((cl-cc/runtime/clos:*rt-class-registry* (make-hash-table :test #'eq))
        (cl-cc/runtime/clos:*rt-generic-function-registry* (make-hash-table :test #'equal)))
    (let* ((base (cl-cc/runtime/clos:rt-defclass 'rt-base '() '(x)))
           (child (cl-cc/runtime/clos:rt-defclass 'rt-child '(rt-base) '(y)))
           (obj (make-hash-table :test #'eq))
           (gf (make-hash-table :test #'equal)))
      (setf (gethash :__class__ obj) child
            (gethash :__name__ gf) 'rt-inherited)
      (cl-cc/runtime/clos:rt-register-method
       gf 'rt-base (lambda (_) (declare (ignore _)) :inherited))
      (expect (cl-cc/runtime/clos:rt-class-name base) :to-be 'rt-base)
      (expect (cl-cc/runtime/clos:rt-class-name child) :to-be 'rt-child)
      (expect (cl-cc/runtime/clos:rt-find-class 'rt-child) :to-be child)
      (expect (cl-cc/runtime/clos:rt-class-name
               (cl-cc/runtime/clos:rt-find-class 'rt-base))
              :to-be 'rt-base)
      (expect (cl-cc/runtime/clos:rt-call-generic gf obj) :to-be :inherited))))

(it-sequential "rt-register-method-and-call-generic"
  (let ((cl-cc/runtime/clos:*rt-class-registry* (make-hash-table :test #'eq))
        (cl-cc/runtime/clos:*rt-generic-function-registry* (make-hash-table :test #'equal)))
    (let* ((klass (cl-cc/runtime/clos:rt-defclass 'rt-node '() '(value)))
           (obj   (make-hash-table :test #'eq))
           (gf    (make-hash-table :test #'equal)))
      (setf (gethash :__class__ obj) klass
            (gethash :__name__  gf)  'rt-describe)
      (cl-cc/runtime/clos:rt-register-method gf 'rt-node
        (lambda (instance)
          (gethash :__name__ (gethash :__class__ instance))))
      (expect (cl-cc/runtime/clos:rt-call-generic gf obj) :to-be 'rt-node))))

(it-sequential "rt-compute-applicable-methods-returns-primary-descriptor"
  (let ((cl-cc/runtime/clos:*rt-class-registry* (make-hash-table :test #'eq))
        (cl-cc/runtime/clos:*rt-generic-function-registry* (make-hash-table :test #'equal)))
    (let* ((base (cl-cc/runtime/clos:rt-defclass 'rt-node '() '(value)))
           (child (cl-cc/runtime/clos:rt-defclass 'rt-child '(rt-node) '()))
           (obj (make-hash-table :test #'eq))
           (gf (make-hash-table :test #'equal))
           (child-calls 0))
      (setf (gethash :__class__ obj) child
            (gethash :__name__ gf) 'rt-primary-selection)
      (cl-cc/runtime/clos:rt-register-method gf 'rt-node
       (lambda (_) (declare (ignore _)) :base))
      (cl-cc/runtime/clos:rt-register-method gf 'rt-child
       (lambda (_) (declare (ignore _)) (incf child-calls) :child))
      (expect (= 2 (length (cl-cc/runtime/clos:rt-compute-applicable-methods gf (list obj))))
              :to-be-truthy)
      (expect (cl-cc/runtime/clos:rt-call-generic gf obj) :to-be :child)
      (expect (= 1 child-calls) :to-be-truthy))))

(it-sequential "rt-eql-specializer-p-cases eql-form"
  (let ((gf (make-hash-table :test #'equal)))
    (setf (gethash :__name__ gf) 'rt-eql-direct)
    (cl-cc/runtime/clos:rt-register-method gf '(eql 42)
     (lambda (_) (declare (ignore _)) :eql))
    (expect (cl-cc/runtime/clos:rt-call-generic gf 42) :to-be :eql)))

(it-sequential "rt-eql-specializer-p-cases non-eql"
  (let ((gf (make-hash-table :test #'equal)))
    (setf (gethash :__name__ gf) 'rt-eql-nonmatch)
    (cl-cc/runtime/clos:rt-register-method gf '(eql 42)
     (lambda (_) (declare (ignore _)) :eql))
    (cl-cc/runtime/clos:rt-register-method gf t
     (lambda (_) (declare (ignore _)) :fallback))
    (expect (cl-cc/runtime/clos:rt-call-generic gf 43) :to-be :fallback)))

(it-sequential "rt-eql-specializer-p-cases not-cons"
  (let ((gf (make-hash-table :test #'equal)))
    (setf (gethash :__name__ gf) 'rt-eql-symbol-fallback)
    (cl-cc/runtime/clos:rt-register-method gf '(eql 42)
     (lambda (_) (declare (ignore _)) :eql))
    (cl-cc/runtime/clos:rt-register-method gf t
     (lambda (_) (declare (ignore _)) :fallback))
    (expect (cl-cc/runtime/clos:rt-call-generic gf 'symbol) :to-be :fallback)))

(it-sequential "rt-eql-specializer-p-cases bare-eql"
  (let ((gf (make-hash-table :test #'equal)))
    (setf (gethash :__name__ gf) 'rt-eql-keyword-fallback)
    (cl-cc/runtime/clos:rt-register-method gf '(eql :read)
     (lambda (_) (declare (ignore _)) :eql))
    (cl-cc/runtime/clos:rt-register-method gf t
     (lambda (_) (declare (ignore _)) :fallback))
    (expect (cl-cc/runtime/clos:rt-call-generic gf :write) :to-be :fallback)))

(it-sequential "rt-extract-eql-specializer-keys-cases direct"
  (let ((gf (make-hash-table :test #'equal)))
    (setf (gethash :__name__ gf) 'rt-eql-key-direct)
    (cl-cc/runtime/clos:rt-register-method gf '(eql 42)
     (lambda (_) (declare (ignore _)) :direct))
    (expect (cl-cc/runtime/clos:rt-call-generic gf 42) :to-be :direct)))

(it-sequential "rt-extract-eql-specializer-keys-cases wrapped"
  (let ((gf (make-hash-table :test #'equal)))
    (setf (gethash :__name__ gf) 'rt-eql-key-wrapped)
    (cl-cc/runtime/clos:rt-register-method gf '((eql 42))
     (lambda (_) (declare (ignore _)) :wrapped))
    (expect (cl-cc/runtime/clos:rt-call-generic gf 42) :to-be :wrapped)))

(it-sequential "rt-extract-eql-specializer-keys-cases non-eql"
  (let ((gf (make-hash-table :test #'equal)))
    (setf (gethash :__name__ gf) 'rt-eql-key-integer)
    (cl-cc/runtime/clos:rt-register-method gf 'integer
     (lambda (_) (declare (ignore _)) :integer))
    (expect (cl-cc/runtime/clos:rt-call-generic gf 42) :to-be :integer)))

(it-sequential "rt-extract-eql-specializer-keys-cases symbol"
  (let ((gf (make-hash-table :test #'equal)))
    (setf (gethash :__name__ gf) 'rt-eql-key-symbol)
    (cl-cc/runtime/clos:rt-register-method gf 'symbol
     (lambda (_) (declare (ignore _)) :symbol))
    (expect (cl-cc/runtime/clos:rt-call-generic gf 'name) :to-be :symbol)))

(it-sequential "rt-call-generic-eql-dispatch"
  (let ((cl-cc/runtime/clos:*rt-generic-function-registry* (make-hash-table :test #'equal)))
    (let ((gf (make-hash-table :test #'equal)))
      (setf (gethash :__name__ gf) 'rt-eql-test-gf)
      (cl-cc/runtime/clos:rt-register-method gf '(eql 99) (lambda (x) (* x 2)))
      (expect (= 1 (length (cl-cc/runtime/clos:rt-compute-applicable-methods gf '(99))))
              :to-be-truthy)
      (expect (= 198 (cl-cc/runtime/clos:rt-call-generic gf 99)) :to-be-truthy))))

(it-sequential "rt-call-generic-eql-index-precedes-class-fallback"
  (let ((gf (make-hash-table :test #'equal)))
    (setf (gethash :__name__ gf) 'rt-eql-fallback-test-gf)
    (cl-cc/runtime/clos:rt-register-method gf 'symbol (lambda (x) (declare (ignore x)) :class))
    (cl-cc/runtime/clos:rt-register-method gf '(eql :read) (lambda (x) (declare (ignore x)) :eql))
    (expect (cl-cc/runtime/clos:rt-call-generic gf :read) :to-be :eql)
    (expect (cl-cc/runtime/clos:rt-call-generic gf :write) :to-be :class)))

(it-sequential "rt-call-generic-standard-method-combination-runs-before-primary-after"
  (let ((cl-cc/runtime/clos:*rt-class-registry* (make-hash-table :test #'eq)))
    (let* ((klass (cl-cc/runtime/clos:rt-defclass 'rt-combo-node '() '()))
           (obj (make-hash-table :test #'eq))
           (log '())
           (gf (make-hash-table :test #'equal)))
      (setf (gethash :__class__ obj) klass
            (gethash :__name__ gf) 'rt-combo)
      (cl-cc/runtime/clos:rt-register-method gf '(:__BEFORE__ rt-combo-node)
                                        (lambda (_) (declare (ignore _)) (push :before log)))
      (cl-cc/runtime/clos:rt-register-method gf 'rt-combo-node
                                        (lambda (_) (declare (ignore _)) (push :primary log) :ok))
      (cl-cc/runtime/clos:rt-register-method gf '(:__AFTER__ rt-combo-node)
                                        (lambda (_) (declare (ignore _)) (push :after-1 log)))
      (cl-cc/runtime/clos:rt-register-method gf '(:__AFTER__ t)
                                        (lambda (_) (declare (ignore _)) (push :after-2 log)))
      (expect (cl-cc/runtime/clos:rt-call-generic gf obj) :to-be :ok)
      (expect log :to-equal '(:after-1 :after-2 :primary :before)))))

(it-sequential "rt-call-generic-custom-method-combination-folds-qualified-methods"
  (let ((cl-cc/runtime/clos:*rt-class-registry* (make-hash-table :test #'eq)))
    (let* ((klass (cl-cc/runtime/clos:rt-defclass 'rt-sum-node '() '()))
           (obj (make-hash-table :test #'eq))
           (gf (make-hash-table :test #'equal)))
      (setf (gethash :__class__ obj) klass
            (gethash :__name__ gf) 'rt-sum
            (gethash :__method-combination__ gf) '+)
      (cl-cc/runtime/clos:rt-register-method gf '(:__+__ rt-sum-node)
                                        (lambda (_) (declare (ignore _)) 10))
      (cl-cc/runtime/clos:rt-register-method gf '(:__+__ t)
                                        (lambda (_) (declare (ignore _)) 7))
      (expect (= 17 (cl-cc/runtime/clos:rt-call-generic gf obj)) :to-be-truthy))))

(it-sequential "rt-register-method-with-qualifier-normalizes-qualified-key"
  (let ((gf (make-hash-table :test #'equal))
        (events '()))
    (setf (gethash :__name__ gf) 'rt-qualified-method)
    (cl-cc/runtime/clos:rt-register-method gf t
     (lambda (_) (declare (ignore _)) (push :before events)) :before)
    (cl-cc/runtime/clos:rt-register-method gf t
     (lambda (_) (declare (ignore _)) :primary))
    (expect (and (eq :primary (cl-cc/runtime/clos:rt-call-generic gf :argument))
                 (equal events '(:before)))
            :to-be-truthy)))

(it-sequential "rt-classify-arg-primitive-types integer"
  (let ((gf (make-hash-table :test #'equal)))
    (setf (gethash :__name__ gf) 'rt-classifier-integer)
    (cl-cc/runtime/clos:rt-register-method gf 'integer
     (lambda (_) (declare (ignore _)) 'integer))
    (expect (cl-cc/runtime/clos:rt-call-generic gf 42) :to-be 'integer)))

(it-sequential "rt-classify-arg-primitive-types string"
  (let ((gf (make-hash-table :test #'equal)))
    (setf (gethash :__name__ gf) 'rt-classifier-string)
    (cl-cc/runtime/clos:rt-register-method gf 'string
     (lambda (_) (declare (ignore _)) 'string))
    (expect (cl-cc/runtime/clos:rt-call-generic gf "hello") :to-be 'string)))

(it-sequential "rt-classify-arg-primitive-types symbol"
  (let ((gf (make-hash-table :test #'equal)))
    (setf (gethash :__name__ gf) 'rt-classifier-symbol)
    (cl-cc/runtime/clos:rt-register-method gf 'symbol
     (lambda (_) (declare (ignore _)) 'symbol))
    (expect (cl-cc/runtime/clos:rt-call-generic gf 'foo) :to-be 'symbol)))

(it-sequential "rt-classify-arg-primitive-types unknown"
  (let ((gf (make-hash-table :test #'equal)))
    (setf (gethash :__name__ gf) 'rt-classifier-fallback)
    (cl-cc/runtime/clos:rt-register-method gf t
     (lambda (_) (declare (ignore _)) :fallback))
    (expect (cl-cc/runtime/clos:rt-call-generic gf 3.14) :to-be :fallback)))

(it-sequential "rt-classify-arg-primitive-types vector"
  (let ((gf (make-hash-table :test #'equal)))
    (setf (gethash :__name__ gf) 'rt-classifier-vector)
    (cl-cc/runtime/clos:rt-register-method gf t (lambda (arg) (declare (ignore arg)) :fallback))
    (expect (cl-cc/runtime/clos:rt-call-generic gf (vector 1 2 3)) :to-be :fallback)))

(it-sequential "rt-classify-arg-clos-descriptor"
  (let* ((cl-cc/runtime/clos:*rt-class-registry* (make-hash-table :test #'eq))
         (class (cl-cc/runtime/clos:rt-defclass 'my-class '() '()))
         (obj (make-hash-table :test #'eq))
         (gf (make-hash-table :test #'equal)))
    (setf (gethash :__class__ obj) class
          (gethash :__name__ gf) 'rt-class-descriptor-dispatch)
    (cl-cc/runtime/clos:rt-register-method gf 'my-class
     (lambda (_) (declare (ignore _)) :class))
    (cl-cc/runtime/clos:rt-register-method gf t
     (lambda (_) (declare (ignore _)) :fallback))
    (expect (cl-cc/runtime/clos:rt-call-generic gf obj) :to-be :class)))

(it-sequential "rt-classify-arg-plain-hash-table-returns-t"
  (let ((ht (make-hash-table :test #'eq))
        (gf (make-hash-table :test #'equal)))
    (setf (gethash :__name__ gf) 'rt-classifier-plain-hash)
    (cl-cc/runtime/clos:rt-register-method gf t
     (lambda (_) (declare (ignore _)) :fallback))
    (expect (cl-cc/runtime/clos:rt-call-generic gf ht) :to-be :fallback)))

(it-sequential "rt-primitive-type-classifiers-table-entries"
  (let ((gf (make-hash-table :test #'equal)))
    (setf (gethash :__name__ gf) 'rt-primitive-classifier-behavior)
    (cl-cc/runtime/clos:rt-register-method gf 'integer
     (lambda (_) (declare (ignore _)) :integer))
    (cl-cc/runtime/clos:rt-register-method gf 'string
     (lambda (_) (declare (ignore _)) :string))
    (cl-cc/runtime/clos:rt-register-method gf 'symbol
     (lambda (_) (declare (ignore _)) :symbol))
    (cl-cc/runtime/clos:rt-register-method gf t
     (lambda (_) (declare (ignore _)) :fallback))
    (expect (cl-cc/runtime/clos:rt-call-generic gf 42) :to-be :integer)
    (expect (cl-cc/runtime/clos:rt-call-generic gf "hello") :to-be :string)
    (expect (cl-cc/runtime/clos:rt-call-generic gf 'foo) :to-be :symbol)
    (expect (cl-cc/runtime/clos:rt-call-generic gf 3.14) :to-be :fallback)))

(it-sequential "rt-slot-ops"
  (let ((obj (make-instance 'rt-clos-test-fixture :x 42)))
    (expect (= 42 (cl-cc/runtime/clos:rt-slot-value obj 'x)) :to-be-truthy)
    (cl-cc/runtime/clos:rt-slot-set obj 'x 99)
    (expect (= 99 (cl-cc/runtime/clos:rt-slot-value obj 'x)) :to-be-truthy)
    (expect (= 1 (cl-cc/runtime/clos:rt-slot-boundp   obj 'x)) :to-be-truthy)
    (expect (= 1 (cl-cc/runtime/clos:rt-slot-exists-p obj 'x)) :to-be-truthy)
    (expect (= 0 (cl-cc/runtime/clos:rt-slot-exists-p obj 'nonexistent)) :to-be-truthy)
    (cl-cc/runtime/clos:rt-slot-makunbound obj 'x)
    (expect (= 0 (cl-cc/runtime/clos:rt-slot-boundp obj 'x)) :to-be-truthy)))

(it-sequential "rt-class-name-and-of"
  (let ((ht (make-hash-table :test #'eq)))
    (setf (gethash :__name__ ht) 'my-class)
    (expect (cl-cc/runtime/clos:rt-class-name ht) :to-be 'my-class))
  (let ((obj (make-instance 'rt-clos-test-fixture :x 1)))
    (expect (class-name (cl-cc/runtime/clos:rt-class-of obj)) :to-be 'rt-clos-test-fixture)))

(it-sequential "rt-cpl-walk-stops-at-already-seen"
  (let ((cl-cc/runtime/clos:*rt-class-registry* (make-hash-table :test #'eq))
        (cl-cc/runtime/clos:*rt-generic-function-registry* (make-hash-table :test #'equal)))
    (let* ((root (cl-cc/runtime/clos:rt-defclass 'cpl-root '() '()))
           (left (cl-cc/runtime/clos:rt-defclass 'cpl-left '(cpl-root) '()))
           (right (cl-cc/runtime/clos:rt-defclass 'cpl-right '(cpl-root) '()))
           (leaf (cl-cc/runtime/clos:rt-defclass 'cpl-leaf '(cpl-left cpl-right) '()))
           (obj (make-hash-table :test #'eq))
           (gf (make-hash-table :test #'equal)))
      (declare (ignore root left right))
      (setf (gethash :__class__ obj) leaf
            (gethash :__name__ gf) 'rt-cpl-diamond)
      (cl-cc/runtime/clos:rt-register-method gf 'cpl-root
       (lambda (_) (declare (ignore _)) :root))
      (expect (cl-cc/runtime/clos:rt-call-generic gf obj) :to-be :root))))

(it-sequential "rt-cpl-walk-single-class-no-supers"
  (let ((cl-cc/runtime/clos:*rt-class-registry* (make-hash-table :test #'eq))
        (cl-cc/runtime/clos:*rt-generic-function-registry* (make-hash-table :test #'equal)))
    (let* ((class (cl-cc/runtime/clos:rt-defclass 'cpl-base '() '()))
           (obj (make-hash-table :test #'eq))
           (gf (make-hash-table :test #'equal)))
      (setf (gethash :__class__ obj) class
            (gethash :__name__ gf) 'rt-cpl-base-dispatch)
      (cl-cc/runtime/clos:rt-register-method gf 'cpl-base
       (lambda (_) (declare (ignore _)) :base))
      (expect (cl-cc/runtime/clos:rt-call-generic gf obj) :to-be :base))))

(it-sequential "rt-cpl-walk-inherits-parent"
  (let ((cl-cc/runtime/clos:*rt-class-registry* (make-hash-table :test #'eq))
        (cl-cc/runtime/clos:*rt-generic-function-registry* (make-hash-table :test #'equal)))
    (let* ((parent (cl-cc/runtime/clos:rt-defclass 'cpl-parent '() '()))
           (child (cl-cc/runtime/clos:rt-defclass 'cpl-child '(cpl-parent) '()))
           (obj (make-hash-table :test #'eq))
           (gf (make-hash-table :test #'equal)))
      (declare (ignore parent))
      (setf (gethash :__class__ obj) child
            (gethash :__name__ gf) 'rt-cpl-inheritance)
      (cl-cc/runtime/clos:rt-register-method gf 'cpl-parent
       (lambda (_) (declare (ignore _)) :parent))
      (cl-cc/runtime/clos:rt-register-method gf 'cpl-child
       (lambda (_) (declare (ignore _)) :child))
      (expect (cl-cc/runtime/clos:rt-call-generic gf obj) :to-be :child)
      (expect (= 2 (length (cl-cc/runtime/clos:rt-compute-applicable-methods gf (list obj))))
              :to-be-truthy)
      (expect (cl-cc/runtime/clos:rt-class-name
               (cl-cc/runtime/clos:rt-find-class 'cpl-child))
              :to-be 'cpl-child))))
