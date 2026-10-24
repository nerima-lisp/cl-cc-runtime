;;;; runtime-clos-applicability.lisp — Method applicability and specificity
;;;; ranking (rt-compute-applicable-methods), split out of
;;;; runtime-clos-dispatch.lisp
(in-package :cl-cc/runtime)

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
