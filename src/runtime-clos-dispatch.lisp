;;;; runtime-clos-dispatch — generic-function & method dispatch: specializers, applicable methods,
;;;; method combination

(in-package :cl-cc/runtime)

;;; ------------------------------------------------------------
;;; EQL Specializer Support
;;; ------------------------------------------------------------

(defun %rt-eql-specializer-p (key)
  (and (consp key) (eq (car key) 'eql)))

(defun %rt-extract-eql-specializer-keys (specializer)
  (cond
    ((%rt-eql-specializer-p specializer)
     (list (second specializer)))
    ((and (consp specializer)
          (= (length specializer) 1)
          (%rt-eql-specializer-p (car specializer)))
     (list (second (car specializer))))
     (t nil)))

(defun %rt-qualified-keyword-p (key)
  "Return true when KEY is a runtime qualified method-table keyword (:__X__)."
  (and (keywordp key)
       (let ((name (symbol-name key)))
         (and (> (length name) 4)
              (string= name "__" :end1 2)
              (string= name "__" :start1 (- (length name) 2))))))

(defun %rt-method-key-qualifier (specs)
  "Return qualifier keyword for SPECS, or NIL for primary methods.

Accepted qualified forms:
- (:__BEFORE__ class)
- (:__AFTER__ class)
- (:__AROUND__ class)
- custom method-combination keys such as (:__+__ class)"
  (when (and (consp specs)
              (= (length specs) 2)
              (%rt-qualified-keyword-p (first specs)))
    (first specs)))

(defun %rt-method-key-specializer (specs)
  "Return the base specializer key from SPECS.

Qualified method keys like `(:__BEFORE__ class)` normalize to `class` for
classification/EQL indexing purposes; unqualified keys return unchanged." 
  (or (and (%rt-method-key-qualifier specs)
           (second specs))
      specs))

(defun %rt-qualifier->key (qualifier)
  "Normalize QUALIFIER (:before, BEFORE, or :__BEFORE__) to a dispatch key."
  (cond
    ((null qualifier) nil)
    ((%rt-qualified-keyword-p qualifier) qualifier)
    (t (intern (format nil "__~A__" (string-upcase (string qualifier))) :keyword))))

(defun %rt-gf-registry-key (gf)
  "Return the generic-function registry key for descriptor GF."
  (or (and (hash-table-p gf) (gethash :__name__ gf)) gf))

(defun %rt-ensure-gf-registry-entry (gf)
  "Return the registry entry for GF, creating it when necessary."
  (let* ((key (%rt-gf-registry-key gf))
         (entry (gethash key *rt-generic-function-registry*)))
    (unless entry
      (setf entry (cons nil (make-hash-table :test #'eq))
            (gethash key *rt-generic-function-registry*) entry))
    entry))

(defun %rt-method-function (method)
  "Extract the callable function from a runtime method descriptor or value."
  (cond
    ((hash-table-p method)
     (or (gethash :function method)
         (error "Runtime method descriptor missing :function")))
    (t method)))

(defun %rt-method-qualifier-key (method)
  (and (hash-table-p method) (gethash :qualifier-key method)))

(defun %rt-method-specializer (method)
  (if (hash-table-p method) (gethash :specializer method) t))

(defun %rt-method-order (method)
  (if (hash-table-p method) (gethash :order method) 0))

(defun %rt-method-matches-qualifier-p (method qualifier-key)
  (eq (%rt-method-qualifier-key method) qualifier-key))

(defun %rt-recompute-dispatch-info (gf)
  "Recompute derived dispatch metadata for GF's registry entry."
  (let* ((entry (%rt-ensure-gf-registry-entry gf))
         (info (cdr entry))
         (methods (copy-list (car entry))))
    (setf (gethash :methods info) methods
          (gethash :primary-methods info)
          (remove-if-not (lambda (m) (%rt-method-matches-qualifier-p m nil)) methods)
          (gethash :qualified-methods info)
          (remove-if (lambda (m) (%rt-method-matches-qualifier-p m nil)) methods))
    info))

;;; ------------------------------------------------------------
;;; Generic Dispatch
;;; ------------------------------------------------------------

(defparameter *rt-primitive-type-classifiers*
  '((integer . integer)
    (string  . string)
    (symbol  . symbol))
  "Ordered (CL-type . dispatch-name) pairs for primitive argument classification.
Used by %rt-classify-arg for generic dispatch on non-CLOS values.")

(defun %rt-classify-arg (arg)
  "Return the dispatch type name for ARG.
CLOS descriptor hash tables → slot :__name__; primitives → *rt-primitive-type-classifiers*."
  (cond
    ((hash-table-p arg)
     (let ((class-ht (gethash :__class__ arg)))
       (if class-ht (gethash :__name__ class-ht) t)))
    ((cdr (assoc-if (lambda (type) (typep arg type))
                    *rt-primitive-type-classifiers*)))
    ((typep arg 'standard-object) (class-name (class-of arg)))
    (t t)))

(defun %rt-arg-cpl (arg)
  "Return ARG's runtime class precedence list, always including T fallback."
  (let* ((class-name (%rt-classify-arg arg))
         (class-ht (gethash class-name *rt-class-registry*))
         (cpl (if class-ht
                  (or (gethash :__cpl__ class-ht) (list class-name))
                  (list class-name))))
    (if (member t cpl :test #'eq) cpl (append cpl (list t)))))

(defun %rt-eql-specializer-matches-p (spec arg)
  (and (%rt-eql-specializer-p spec)
       (eql arg (second spec))))

(defun %rt-specializer-matches-p (spec arg cpl)
  "Return true when SPEC applies to ARG with class precedence list CPL."
  (or (eq spec t)
      (%rt-eql-specializer-matches-p spec arg)
      (member spec cpl :test #'eq)))

(defun %rt-normalize-specializers (specializer arg-count)
  "Return SPECIALIZER as a list of per-argument specializers."
  (cond
    ((and (= arg-count 1) (%rt-eql-specializer-p specializer))
     (list specializer))
    ((and (listp specializer)
          (not (%rt-eql-specializer-p specializer))
          (= (length specializer) arg-count))
     specializer)
    ((= arg-count 1)
     (list specializer))
    (t nil)))

(defun %rt-method-applicable-p (method args cpls)
  "Return true when METHOD applies to ARGS/CPLS."
  (let ((specializers (%rt-normalize-specializers (%rt-method-specializer method)
                                                  (length args))))
    (and specializers
         (every #'%rt-specializer-matches-p specializers args cpls))))

(defun %rt-specializer-rank (spec arg cpl)
  "Return a specificity rank for SPEC on ARG/CPL; lower is more specific."
  (cond
    ((%rt-eql-specializer-matches-p spec arg) -1)
    ((eq spec t) most-positive-fixnum)
    (t (or (position spec cpl :test #'eq) most-positive-fixnum))))

(defun %rt-method-specificity-vector (method args cpls)
  "Return METHOD's lexicographic specificity vector for ARGS/CPLS."
  (mapcar #'%rt-specializer-rank
          (%rt-normalize-specializers (%rt-method-specializer method) (length args))
          args
          cpls))

(defun %rt-specificity< (left right args cpls)
  "True when LEFT should precede RIGHT in most-specific-first dispatch order."
  (let ((lvec (%rt-method-specificity-vector left args cpls))
        (rvec (%rt-method-specificity-vector right args cpls)))
    (labels ((lex< (ls rs)
               (cond
                 ((or (null ls) (null rs)) nil)
                 ((< (first ls) (first rs)) t)
                 ((> (first ls) (first rs)) nil)
                 (t (lex< (rest ls) (rest rs))))))
      (or (lex< lvec rvec)
          (and (equal lvec rvec)
               (> (%rt-method-order left) (%rt-method-order right)))))))

(defun rt-compute-applicable-methods (gf args &optional qualifier)
  "Return applicable methods for GF and ARGS in most-specific-first order.

QUALIFIER may be NIL for primary methods, :before/:after/:around, or a runtime
qualified dispatch key such as :__BEFORE__.  Returned elements are runtime method
descriptors; use %RT-METHOD-FUNCTION to obtain the callable."
  (unless (hash-table-p gf)
    (return-from rt-compute-applicable-methods nil))
  (let* ((entry (%rt-ensure-gf-registry-entry gf))
         (qualifier-key (%rt-qualifier->key qualifier))
         (args-list (copy-list args))
         (cpls (mapcar #'%rt-arg-cpl args-list))
         (methods (remove-if-not
                   (lambda (method)
                     (and (%rt-method-matches-qualifier-p method qualifier-key)
                          (%rt-method-applicable-p method args-list cpls)))
                   (car entry))))
    (stable-sort methods
                 (lambda (left right)
                   (%rt-specificity< left right args-list cpls)))))

(defun rt-register-method (gf specs method &optional qualifier)
  "Register METHOD in GF under SPECS, optionally qualified by QUALIFIER.

When QUALIFIER is provided, SPECS are normalized to a qualified method key
`(:__<QUALIFIER>__ <SPECIALIZER>)` to match runtime dispatch table layout."
  (unless (hash-table-p gf)
    (error "rt-register-method expects a generic-function descriptor hash table, got ~S" gf))
  (let* ((qualifier-key (or (%rt-qualifier->key qualifier)
                            (%rt-method-key-qualifier specs)))
         (specializer (if qualifier
                          specs
                          (%rt-method-key-specializer specs)))
         (normalized-specs (if qualifier-key
                               (list qualifier-key specializer)
                               specializer))
         (methods-ht (or (gethash :__methods__ gf)
                         (setf (gethash :__methods__ gf) (make-hash-table :test #'equal))))
         (eql-index (or (gethash :__eql-index__ gf)
                        (setf (gethash :__eql-index__ gf) (make-hash-table :test #'equal))))
         (entry (%rt-ensure-gf-registry-entry gf))
         (descriptor (make-hash-table :test #'eq)))
    (when (gethash :__satiated__ gf)
      (setf (gethash :__satiated__ gf) nil))
    (incf (gethash '__ic-gen__ gf 0))
    (setf (gethash :function descriptor) method
          (gethash :qualifier-key descriptor) qualifier-key
          (gethash :qualifiers descriptor) (and qualifier-key (list qualifier-key))
          (gethash :specializer descriptor) specializer
          (gethash :key descriptor) normalized-specs
          (gethash :gf descriptor) gf
          (gethash :order descriptor) (incf *rt-method-registration-counter*))
    (setf (car entry)
          (cons descriptor
                (remove-if (lambda (old)
                             (and (eql (%rt-method-qualifier-key old) qualifier-key)
                                  (equal (%rt-method-specializer old) specializer)
                                  (eq (%rt-method-function old) method)))
                           (car entry))))
    ;; Maintain the VM-shaped descriptor tables for native-code bridges and
    ;; compatibility with existing runtime tests/introspection.
    (setf (gethash normalized-specs methods-ht) method)
    (when qualifier-key
      (let ((qual-ht (or (gethash qualifier-key gf)
                         (setf (gethash qualifier-key gf) (make-hash-table :test #'equal)))))
        (if (eq qualifier-key :__AROUND__)
            (push descriptor (gethash specializer qual-ht))
            (push descriptor (gethash specializer qual-ht)))))
    (dolist (key (%rt-extract-eql-specializer-keys specializer))
      (pushnew descriptor (gethash key eql-index) :test #'eq))
    (%rt-recompute-dispatch-info gf)
    method))

(defun %rt-applicable-qualified-methods (gf args qualifier-key)
  "Return applicable qualified descriptors for GF/ARGS."
  (rt-compute-applicable-methods gf args qualifier-key))

(defun %rt-resolve-combination-operator (combination)
  "Resolve custom method-combination COMBINATION symbol to host operator."
  (or (and (symbolp combination)
           (fboundp combination)
           (symbol-function combination))
      (error "Unsupported runtime method combination operator: ~S" combination)))

(defun %rt-invoke-method (gf method args next-thunk)
  "Invoke METHOD with ARGS and dynamic CALL-NEXT-METHOD context."
  (let ((*rt-method-context-stack*
          (cons (list :gf gf :method method :args args :next-thunk next-thunk)
                *rt-method-context-stack*)))
    (apply (%rt-method-function method) args)))

(defun %rt-invoke-primary-chain (gf methods args)
  "Invoke primary METHODS with CALL-NEXT-METHOD chaining."
  (unless methods
    (error "call-next-method: no primary method"))
  (let ((method (first methods))
        (rest-methods (rest methods)))
    (%rt-invoke-method gf method args
                       (and rest-methods
                            (lambda (next-args)
                              (%rt-invoke-primary-chain gf rest-methods next-args))))))

(defun %rt-invoke-standard-core (gf primary-methods before-methods after-methods args)
  "Run standard before → primary chain → after combination and return primary value."
  (dolist (method before-methods)
    (%rt-invoke-method gf method args nil))
  (unless primary-methods
    (error "No applicable runtime generic primary method for ~S on ~S"
           (gethash :__name__ gf) (mapcar #'%rt-classify-arg args)))
  (let ((result (%rt-invoke-primary-chain gf primary-methods args)))
    (dolist (method (reverse after-methods))
      (%rt-invoke-method gf method args nil))
    result))

(defun %rt-invoke-around-chain (gf around-methods core-thunk args)
  "Invoke AROUND-METHODS around CORE-THUNK with CALL-NEXT-METHOD chaining."
  (if (null around-methods)
      (funcall core-thunk args)
      (let ((method (first around-methods))
            (rest-methods (rest around-methods)))
        (%rt-invoke-method gf method args
                           (lambda (next-args)
                             (%rt-invoke-around-chain gf rest-methods core-thunk next-args))))))

(defun %rt-call-custom-combination (gf combination args primary-methods)
  "Call custom method-combination methods for GF."
  (let* ((qual-key (%rt-qualifier->key combination))
         (combo-methods (%rt-applicable-qualified-methods gf args qual-key))
         (methods (or combo-methods primary-methods)))
    (unless methods
      (error "No applicable runtime generic method for ~S with combination ~S on ~S"
             (gethash :__name__ gf) combination (mapcar #'%rt-classify-arg args)))
    (apply (%rt-resolve-combination-operator combination)
           (mapcar (lambda (m) (%rt-invoke-method gf m args nil)) methods))))

(defun rt-call-generic (gf &rest args)
  "Dispatch GF over ARGS using the native-runtime CLOS method registry."
  (if (hash-table-p gf)
      (let* ((arg-list (copy-list args))
             (combination (gethash :__method-combination__ gf))
             (primary-methods (rt-compute-applicable-methods gf arg-list nil))
             (before-methods (%rt-applicable-qualified-methods gf arg-list :__BEFORE__))
             (after-methods (%rt-applicable-qualified-methods gf arg-list :__AFTER__))
             (around-methods (%rt-applicable-qualified-methods gf arg-list :__AROUND__)))
        (cond
          ((and combination (not (eq combination 'standard)))
           (%rt-call-custom-combination gf combination arg-list primary-methods))
          ((or around-methods before-methods after-methods)
           (%rt-invoke-around-chain
            gf around-methods
            (lambda (next-args)
              (%rt-invoke-standard-core gf primary-methods before-methods after-methods next-args))
            arg-list))
          (t
           (unless primary-methods
             (error "No applicable runtime generic method for ~S on ~S"
                    (gethash :__name__ gf) (mapcar #'%rt-classify-arg arg-list)))
           (%rt-invoke-primary-chain gf primary-methods arg-list))))
      (apply gf args)))
