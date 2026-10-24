;;;; runtime-dynamic-binding.lisp — Special-variable registration and the
;;;; per-thread dynamic binding stack, split out of runtime-math-io.lisp
(in-package :cl-cc/runtime)

;;; ------------------------------------------------------------
;;; Symbols
;;; ------------------------------------------------------------

(defun rt-make-symbol (name) (make-symbol name))

(defvar *rt-global-var-registry* (make-hash-table :test #'eq)
  "Runtime global variable registry used instead of host symbol-value cells.")

(defstruct (rt-special-variable-metadata (:constructor %make-rt-special-variable-metadata))
  "Metadata for runtime special variables.

GLOBAL-ONLY-P remains true until the symbol is dynamically bound.  GC scanners
can skip global-only variables when walking binding stacks because their value is
kept in *RT-GLOBAL-VAR-REGISTRY* rather than in thread-local dynamic frames."
  symbol
  (global-only-p t :type boolean))

(defvar *rt-special-variable-metadata* (make-hash-table :test #'eq)
  "Symbol -> RT-SPECIAL-VARIABLE-METADATA.")

(defvar *rt-dynamic-binding-stacks* (make-hash-table :test #'equal)
  "Logical thread id -> stack of runtime dynamic binding frames.")

(defparameter *rt-current-binding-thread-id* :main
  "Current logical thread id for runtime dynamic special bindings.")

(defun rt-register-special-variable (sym &key (global-only-p t))
  "Register SYM as a special variable and return its metadata object."
  (let ((metadata (or (gethash sym *rt-special-variable-metadata*)
                      (%make-rt-special-variable-metadata :symbol sym))))
    (setf (rt-special-variable-metadata-global-only-p metadata) global-only-p
          (gethash sym *rt-special-variable-metadata*) metadata)
    metadata))

(defun rt-special-variable-global-only-p (sym)
  "Return true when SYM has never been dynamically bound."
  (let ((metadata (gethash sym *rt-special-variable-metadata*)))
    (or (null metadata)
        (rt-special-variable-metadata-global-only-p metadata))))

(defun %rt-binding-symbol (binding)
  ;; A plist frame is (:symbol S :value V); a compact frame is the dotted cons
  ;; (S . V) produced by RT-DYNAMIC-BIND.  Only proper-list frames may be probed
  ;; with GETF — calling GETF on a dotted cons signals "malformed property list".
  (cond
    ((and (consp binding) (consp (cdr binding)) (getf binding :symbol))
     (getf binding :symbol))
    ((consp binding) (car binding))
    (t nil)))

(defun %rt-binding-value (binding)
  (cond
    ((and (consp binding) (consp (cdr binding)) (getf binding :value))
     (getf binding :value))
    ((consp binding) (cdr binding))
    (t nil)))

(defun %rt-set-binding-value (binding value)
  (cond
    ((and (consp binding) (consp (cdr binding)) (getf binding :value))
     (setf (getf binding :value) value))
    ((consp binding)
     (setf (cdr binding) value)))
  binding)

(defun %rt-current-binding-stack (&optional (thread-id *rt-current-binding-thread-id*))
  (gethash thread-id *rt-dynamic-binding-stacks*))

(defun rt-dynamic-bind (sym value &optional (thread-id *rt-current-binding-thread-id*))
  "Push a dynamic binding for special variable SYM on THREAD-ID's binding stack."
  (let ((metadata (rt-register-special-variable sym :global-only-p nil)))
    (setf (rt-special-variable-metadata-global-only-p metadata) nil)
    (push (cons sym value) (gethash thread-id *rt-dynamic-binding-stacks*))
    value))

(defun rt-dynamic-unbind (&optional (thread-id *rt-current-binding-thread-id*))
  "Pop the most recent dynamic binding for THREAD-ID."
  (let ((stack (gethash thread-id *rt-dynamic-binding-stacks*)))
    (when stack
      (prog1 (pop stack)
        (setf (gethash thread-id *rt-dynamic-binding-stacks*) stack)))))

(defmacro rt-with-dynamic-binding
    ((sym value &optional (thread-id '*rt-current-binding-thread-id*))
     &body body)
  "Execute BODY with SYM dynamically bound to VALUE for THREAD-ID."
  (let ((tid (gensym "THREAD-ID")))
    `(let ((,tid ,thread-id))
       (rt-dynamic-bind ,sym ,value ,tid)
       (unwind-protect
            (progn ,@body)
         (rt-dynamic-unbind ,tid)))))

(defun %rt-dynamic-binding-cell (sym &optional (thread-id *rt-current-binding-thread-id*))
  (find sym (%rt-current-binding-stack thread-id)
        :key #'%rt-binding-symbol
        :test #'eq))

(defun rt-symbol-value (sym)
  (let ((binding (%rt-dynamic-binding-cell sym)))
    (if binding
        (%rt-binding-value binding)
        (multiple-value-bind (value present-p) (gethash sym *rt-global-var-registry*)
          (if present-p
              value
              (error "Unbound runtime variable: ~S" sym))))))

(defun rt-set-symbol-value (sym val)
  (let ((binding (%rt-dynamic-binding-cell sym)))
    (if binding
        (%rt-set-binding-value binding val)
        (progn
          (rt-register-special-variable sym :global-only-p t)
          (setf (gethash sym *rt-global-var-registry*) val))))
  val)
