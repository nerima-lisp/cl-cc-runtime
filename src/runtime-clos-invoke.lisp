;;;; runtime-clos-invoke.lisp — Method invocation and combination
;;;; (rt-call-generic), split out of runtime-clos-dispatch.lisp
(in-package :cl-cc/runtime)

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
