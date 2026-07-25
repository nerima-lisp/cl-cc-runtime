;;;; runtime-list.lisp — Globals, type predicates, cons/list primitives, COW lists, coercions
(in-package :cl-cc/runtime)

;;; ------------------------------------------------------------
;;; Global Bindings
;;; ------------------------------------------------------------

(defun rt-get-global (sym)
  (symbol-value sym))

(defun rt-set-global (sym val)
  (setf (symbol-value sym) val))

;;; ------------------------------------------------------------
;;; Type Predicates
;;; ------------------------------------------------------------

(defmacro define-rt-predicate (name predicate)
  "Define an rt-* unary predicate returning 1/0 based on PREDICATE applied to its argument."
  `(defun ,name (x) (if (,predicate x) 1 0)))

(defmacro define-rt-binary-predicate (name op)
  "Define an rt-* binary predicate returning 1/0 based on OP applied to (a b)."
  `(defun ,name (a b) (if (,op a b) 1 0)))

(define-rt-predicate rt-consp        consp)

(define-rt-predicate rt-null-p       null)

(define-rt-predicate rt-symbolp      symbolp)

(define-rt-predicate rt-numberp      numberp)

(define-rt-predicate rt-integerp     integerp)

(define-rt-predicate rt-floatp       floatp)

(define-rt-predicate rt-stringp      stringp)

(define-rt-predicate rt-characterp   characterp)

(define-rt-predicate rt-vectorp      vectorp)

(define-rt-predicate rt-listp        listp)

(define-rt-predicate rt-atomp        atom)

(define-rt-predicate rt-keywordp     keywordp)

;;; rt-functionp has a compound check — stays explicit
(defun rt-functionp (x)
  (if (or (functionp x) (rt-closure-obj-p x)) 1 0))

(defun rt-typep (x type-name)
  (if (typep x (find-symbol (string type-name) :cl)) 1 0))

(defun rt-type-of (x)
  (type-of x))

;;; ------------------------------------------------------------
;;; Cons / List Operations
;;; ------------------------------------------------------------

(defstruct (rt-cow-list (:constructor %make-rt-cow-list))
  "Runtime copy-on-write list wrapper used by rt-copy-list/rt-rplac* operations."
  (backing nil)
  (refcount 1 :type integer))

(defun %rt-cow-list-materialize (value)
  (if (rt-cow-list-p value)
      (rt-cow-list-backing value)
      value))

(defun %rt-cow-list-ensure-writable (value)
  (if (rt-cow-list-p value)
      (progn
        (when (> (rt-cow-list-refcount value) 1)
          (decf (rt-cow-list-refcount value))
          (setf (rt-cow-list-backing value) (copy-list (rt-cow-list-backing value))
                (rt-cow-list-refcount value) 1))
        (rt-cow-list-backing value))
      value))

(defun rt-cons (car cdr) (cons car cdr))

(defun rt-car (x) (car (%rt-cow-list-materialize x)))

(defun rt-cdr (x) (cdr (%rt-cow-list-materialize x)))

(defun rt-rplaca (cons val)
  (rplaca (%rt-cow-list-ensure-writable cons) val)
  nil)

(defun rt-rplacd (cons val)
  (rplacd (%rt-cow-list-ensure-writable cons) val)
  nil)

(defun rt-make-list (n &optional (init nil)) (make-list n :initial-element init))

(defun rt-list-length (l) (length (%rt-cow-list-materialize l)))

(defun rt-nconc (a b) (nconc (%rt-cow-list-ensure-writable a)
                            (%rt-cow-list-materialize b)))

(defun rt-reverse (l) (reverse (%rt-cow-list-materialize l)))

(defun rt-nreverse (l) (nreverse (%rt-cow-list-ensure-writable l)))

(defun rt-member (x l) (member x (%rt-cow-list-materialize l)))

(defun rt-nth (n l) (nth n (%rt-cow-list-materialize l)))

(defun rt-nthcdr (n l) (nthcdr n (%rt-cow-list-materialize l)))

(defun rt-last (l) (last (%rt-cow-list-materialize l)))

(defun rt-butlast (l) (butlast (%rt-cow-list-materialize l)))

(defun rt-copy-list (l)
  (let ((materialized (%rt-cow-list-materialize l)))
    ;; Always return a COW wrapper so writes through rt-rplac* remain isolated.
    (%make-rt-cow-list :backing materialized :refcount 2)))

(defun rt-copy-tree (l) (copy-tree l))

(defun rt-assoc (key alist) (assoc key alist))

(defun rt-acons (key val alist) (acons key val alist))

(defun rt-subst (new old tree) (subst new old tree))

(defun rt-first (l) (first l))

(defun rt-second (l) (second l))

(defun rt-third (l) (third l))

(defun rt-fourth (l) (fourth l))

(defun rt-fifth (l) (fifth l))

(defun rt-rest (l) (rest l))

(define-rt-predicate rt-endp endp)

(define-rt-predicate rt-null null)

(defun rt-push-list (val list-place) (cons val list-place))

(defun rt-pop-list (list-place)
  (let ((list-value (%rt-cow-list-materialize list-place)))
    (values (car list-value) (cdr list-value))))

(define-rt-binary-predicate rt-equal equal)

(defun rt-string-coerce (x) (string x))

(defun rt-coerce-to-string (x) (if (stringp x) x (format nil "~A" x)))

(defun rt-coerce-to-list (x) (coerce x 'list))

(defun rt-coerce-to-vector (x) (coerce x 'vector))
