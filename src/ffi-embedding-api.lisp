;;;; ffi-embedding-api.lisp — The cl-cc-* C embedding API (FR-812): lets C
;;;; code call INTO this runtime, the reverse direction of ffi.lisp. Split
;;;; out of ffi.lisp.
(in-package :cl-cc/runtime)

;;; ── C embedding API (FR-812) ──

(defstruct cl-cc-error
  "Last embedding error visible through cl-cc-last-error."
  (code 0 :type integer)
  (message "" :type string))

(defstruct cl-cc-value
  "Host-side representation of a value returned through the embedding API."
  (kind :nil :type keyword)
  (payload nil))

(defstruct cl-cc-state
  "Embeddable VM state owned by a host process."
  (id 0 :type integer)
  (vm nil)
  (package nil)
  (callbacks (make-hash-table :test #'equal))
  (last-error (make-cl-cc-error))
  (closed-p nil :type boolean)
  (lock (cl-cc/runtime:rt-make-lock "cl-cc embedding state lock")))

(defvar *cl-cc-next-state-id* 0)

(defun %cl-cc-find-symbol (package-name symbol-name)
  "Find SYMBOL-NAME in PACKAGE-NAME and return NIL when unavailable."
  (let ((package (find-package package-name)))
    (and package (find-symbol symbol-name package))))

(defun %cl-cc-call-symbol (package-name symbol-name &rest args)
  "Call PACKAGE-NAME::SYMBOL-NAME when it is fbound, otherwise return NIL."
  (let ((symbol (%cl-cc-find-symbol package-name symbol-name)))
    (when (and symbol (fboundp symbol))
      (apply (symbol-function symbol) args))))

(defun %cl-cc-make-vm ()
  "Create a cl-cc VM instance when the VM package is loaded."
  (%cl-cc-call-symbol "CL-CC/VM" "MAKE-VM-INSTANCE"))

(defun %cl-cc-set-error (state code message &rest args)
  "Record an embedding error on STATE."
  (let ((error (make-cl-cc-error :code code
                                 :message (apply #'format nil message args))))
    (setf (cl-cc-state-last-error state) error)
    error))

(defun %cl-cc-clear-error (state)
  "Reset STATE's last-error object to success."
  (setf (cl-cc-state-last-error state) (make-cl-cc-error)))

(defun %cl-cc-wrap-value (value)
  "Wrap a host Lisp value as cl-cc-value."
  (make-cl-cc-value
   :kind (cond
           ((null value) :nil)
           ((integerp value) :integer)
           ((floatp value) :float)
           ((stringp value) :string)
           ((symbolp value) :symbol)
           ((functionp value) :function)
           (t :object))
   :payload value))

(defun %cl-cc-state-package-name (id)
  (format nil "CL-CC/EMBED-~D" id))

(defun %cl-cc-read-forms (code)
  "Read all forms from CODE without enabling reader eval."
  (let ((*read-eval* nil)
        (forms nil))
    (with-input-from-string (in code)
      (loop for form = (read in nil in)
            until (eq form in)
            do (push form forms)))
    (nreverse forms)))

(defun %cl-cc-host-eval (state code)
  "Evaluate CODE in STATE's isolated host package."
  (let ((*package* (cl-cc-state-package state)))
    (loop for form in (%cl-cc-read-forms code)
          for result = (eval form)
          finally (return result))))

(defun %cl-cc-vm-eval (state code)
  "Evaluate CODE in STATE using host CL eval in the state's isolated package."
  (%cl-cc-host-eval state code))

(defun cl-cc-init ()
  "Initialize and return an embeddable cl-cc state object."
  (let* ((id (incf *cl-cc-next-state-id*))
         (package (make-package (%cl-cc-state-package-name id) :use '(:cl)))
         (state (make-cl-cc-state :id id :vm (%cl-cc-make-vm) :package package)))
    state))

(defun cl-cc-eval (state code)
  "Evaluate CODE in STATE and return a cl-cc-value."
  (check-type state cl-cc-state)
  (check-type code string)
  (cl-cc/runtime:rt-with-lock ((cl-cc-state-lock state))
    (handler-case
        (progn
          (when (cl-cc-state-closed-p state)
            (error "Embedding state is closed"))
          (%cl-cc-clear-error state)
          (%cl-cc-wrap-value (%cl-cc-vm-eval state code)))
      (error (condition)
        (%cl-cc-set-error state 1 "~A" condition)
        (make-cl-cc-value :kind :error :payload condition)))))

(defun cl-cc-call (state function-name &rest args)
  "Call FUNCTION-NAME in STATE with ARGS and return a cl-cc-value."
  (check-type state cl-cc-state)
  (check-type function-name string)
  (cl-cc/runtime:rt-with-lock ((cl-cc-state-lock state))
    (handler-case
        (progn
          (when (cl-cc-state-closed-p state)
            (error "Embedding state is closed"))
          (%cl-cc-clear-error state)
          (let* ((*package* (cl-cc-state-package state))
                 (symbol (or (find-symbol (string-upcase function-name) *package*)
                             (find-symbol (string-upcase function-name) :cl))))
            (unless (and symbol (fboundp symbol))
              (error "Unknown embedded function: ~A" function-name))
            (%cl-cc-wrap-value (apply (symbol-function symbol) args))))
      (error (condition)
        (%cl-cc-set-error state 2 "~A" condition)
        (make-cl-cc-value :kind :error :payload condition)))))

(defun cl-cc-register-callback (state name function &key (arg-types nil) (return-type :void))
  "Register FUNCTION as a C-callable callback under NAME for STATE."
  (check-type state cl-cc-state)
  (check-type name string)
  (check-type function function)
  (cl-cc/runtime:rt-with-lock ((cl-cc-state-lock state))
    (let ((callback (rt-make-callback function arg-types return-type)))
      (setf (gethash name (cl-cc-state-callbacks state)) callback)
      callback)))

(defun cl-cc-callback (state name)
  "Return a registered C callback pointer/token by NAME."
  (check-type state cl-cc-state)
  (check-type name string)
  (gethash name (cl-cc-state-callbacks state)))

(defun cl-cc-cleanup (state)
  "Release resources associated with STATE."
  (check-type state cl-cc-state)
  (cl-cc/runtime:rt-with-lock ((cl-cc-state-lock state))
    (clrhash (cl-cc-state-callbacks state))
    (setf (cl-cc-state-vm state) nil
          (cl-cc-state-closed-p state) t)
    t))

(defun cl-cc-last-error (state)
  "Return STATE's last embedding error."
  (check-type state cl-cc-state)
  (cl-cc-state-last-error state))
