;;;; runtime-clos-dispatch — generic-function & method registry: keys,
;;;; qualifiers, and rt-register-method. Applicability/specificity
;;;; computation is in runtime-clos-applicability.lisp; method invocation and
;;;; combination is in runtime-clos-invoke.lisp.

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
