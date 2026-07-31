;;;; runtime-conditions.lisp — Package-wide condition base types,
;;;; method-dispatch context, and the runtime handler/restart condition
;;;; system. The unrelated JIT code cache is in runtime-code-cache.lisp.
(in-package :cl-cc/runtime)

;;; ------------------------------------------------------------
;;; Package-wide condition base types
;;; ------------------------------------------------------------
;;;
;;; Every condition this package signals derives from one of these two, so a
;;; caller can catch everything cl-cc/runtime raises with a single clause:
;;; (handler-case ... (rt-runtime-error (c) ...)) or, for non-error signals
;;; such as retry protocols, (rt-runtime-condition (c) ...).

(define-condition rt-runtime-condition (condition) ()
  (:documentation "Base of every condition cl-cc/runtime signals, error or not."))

(define-condition rt-runtime-error (error rt-runtime-condition) ()
  (:documentation "Base of every error cl-cc/runtime signals."))

(defvar *rt-method-context-stack* nil
  "Dynamic stack of native-runtime generic-function method contexts.

Each frame is a plist with at least :NEXT-THUNK and :ARGS.  RT-CALL-NEXT-METHOD
uses this stack to emulate the VM method-call stack for host-backed runtime
dispatch.")

(defun rt-call-next-method (&rest args)
  "Invoke the next applicable native-runtime method.

When ARGS is empty, reuse the current generic-function arguments.  Otherwise use
ARGS as the replacement argument list, matching Common Lisp CALL-NEXT-METHOD
calling convention at the native runtime layer."
  (let* ((ctx (first *rt-method-context-stack*))
         (next-thunk (and ctx (getf ctx :next-thunk))))
    (unless next-thunk
      (error "call-next-method: no next method"))
    (funcall next-thunk (if args args (getf ctx :args)))))

(defun rt-next-method-p ()
  "Return true when a next method is available in the current runtime context."
  (let ((ctx (first *rt-method-context-stack*)))
    (and ctx (getf ctx :next-thunk) t)))

(defun rt-register-function (name fn)
  (setf (symbol-function name) fn))

;;; ------------------------------------------------------------
;;; Runtime Condition / Restart Support (FR-300)
;;; ------------------------------------------------------------

(defstruct (rt-handler (:constructor make-rt-handler (condition-type handler-function)))
  "Runtime condition handler frame."
  condition-type
  handler-function)

(defstruct (rt-restart (:constructor make-rt-restart (name function)))
  "Runtime restart frame."
  name
  function)

(defvar *handler-stack* nil
  "Dynamic stack of runtime condition handlers.

The native backend pushes frames here before signaling conditions.  Each frame
contains a condition type and a handler function; the most recent matching
frame is invoked first.")

(defvar *restart-stack* nil
  "Dynamic stack of runtime restart bindings.

Each frame contains a restart name and a function to call when that restart is
invoked through RT-INVOKE-RESTART.")

(defun rt-push-handler (condition-type handler-function)
  "Push HANDLER-FUNCTION for CONDITION-TYPE onto the runtime handler stack."
  (check-type condition-type (or symbol cons class))
  (check-type handler-function (or function symbol rt-closure-obj))
  (push (make-rt-handler condition-type handler-function) *handler-stack*))

(defun rt-pop-handler ()
  "Pop and return the top runtime handler frame, or NIL when the stack is empty."
  (pop *handler-stack*))

(defun rt-establish-handler (condition-type handler-function thunk)
  "Run THUNK with HANDLER-FUNCTION established for CONDITION-TYPE.

This is the native-runtime analogue of a handler frame save point: the frame is
always removed when THUNK exits, including non-local exits and errors."
  (check-type thunk (or function symbol rt-closure-obj))
  (rt-push-handler condition-type handler-function)
  (unwind-protect
       (rt-call-fn thunk)
    (rt-pop-handler)))

(defun rt-find-handler (condition)
  "Return the most recent runtime handler matching CONDITION, or NIL."
  (find-if (lambda (handler)
             (typep condition (rt-handler-condition-type handler)))
           *handler-stack*))

(defun rt-dispatch-signal (condition)
  "Dispatch CONDITION to the runtime handler stack.

Returns two values: the handler's return value and true when a runtime handler
was found; NIL and NIL otherwise."
  (let ((handler (rt-find-handler condition)))
    (if handler
        (values (rt-call-fn (rt-handler-handler-function handler) condition) t)
        (values nil nil))))

(defun rt-push-restart (name function)
  "Push FUNCTION as the runtime restart named NAME."
  (check-type function (or function symbol rt-closure-obj))
  (push (make-rt-restart name function) *restart-stack*))

(defun rt-pop-restart ()
  "Pop and return the top runtime restart frame, or NIL when the stack is empty."
  (pop *restart-stack*))

(defun rt-find-restart (name)
  "Return the most recent runtime restart named NAME, or NIL."
  (find name *restart-stack* :key #'rt-restart-name :test #'eq))

(defun rt-establish-restart (name function thunk)
  "Run THUNK with FUNCTION established as runtime restart NAME."
  (check-type thunk (or function symbol rt-closure-obj))
  (rt-push-restart name function)
  (unwind-protect
       (rt-call-fn thunk)
    (rt-pop-restart)))

(defun rt-restart-bind (bindings thunk)
  "Run THUNK with runtime restart BINDINGS.

BINDINGS is a list of (NAME FUNCTION) entries.  Frames are removed in
unwind-protect style."
  (labels ((run-with-runtime-bindings (remaining)
             (if (endp remaining)
                 (rt-call-fn thunk)
                 (destructuring-bind (name function) (first remaining)
                   (rt-push-restart name function)
                   (unwind-protect
                        (run-with-runtime-bindings (rest remaining))
                     (rt-pop-restart))))))
    (run-with-runtime-bindings bindings)))

(defun rt-restart-case (thunk clauses)
  "Run THUNK with restart CLAUSES established.

CLAUSES is a list of (NAME FUNCTION) entries.  This function-level API is used
by generated native runtime calls; source-level RESTART-CASE still expands in
the compiler/VM layer."
  (rt-restart-bind clauses thunk))

(defun rt-dispatch-restart (name args)
  "Invoke runtime restart NAME with ARGS.

Returns two values: restart result and true when a runtime restart was found;
NIL and NIL otherwise."
  (let ((restart (rt-find-restart name)))
    (if restart
        (values (apply #'rt-call-fn (rt-restart-function restart) args) t)
        (values nil nil))))
