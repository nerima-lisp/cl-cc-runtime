;;;; runtime-conditions.lisp — Package-wide condition base types,
;;;; method-dispatch context, and the runtime handler/restart condition
;;;; system. The unrelated JIT code cache is in runtime-code-cache.lisp.
(in-package :cl-cc/runtime/conditions)

;;; ------------------------------------------------------------
;;; Package-wide condition base types
;;; ------------------------------------------------------------
;;;
;;; Every condition this package signals derives from one of these two, so a
;;; caller can catch everything cl-cc/runtime raises with a single clause:
;;; (handler-case ... (rt-runtime-error (c) ...)) or, for non-error signals
;;; such as retry protocols, (rt-runtime-condition (c) ...).
(define-condition rt-runtime-condition
  (condition)
  ()
  (:documentation
   "Base of every condition cl-cc/runtime signals, error or not."))

(define-condition rt-runtime-error
  (error rt-runtime-condition)
  ()
  (:documentation "Base of every error cl-cc/runtime signals."))

;;; ANSI condition taxonomy used by runtime-generated errors.  The RT prefix
;;; keeps these classes distinct from host conditions while retaining the
;;; standard superclass relationships callers use with TYPEP.
(define-condition rt-serious-condition
  (serious-condition rt-runtime-condition)
  ())

(define-condition rt-warning
  (warning rt-runtime-condition)
  ())

(define-condition rt-type-error
  (type-error rt-runtime-error)
  ())

(define-condition rt-simple-type-error
  (simple-type-error rt-type-error)
  ())

(define-condition rt-program-error
  (program-error rt-runtime-error)
  ())

(define-condition rt-control-error
  (control-error rt-runtime-error)
  ())

(define-condition rt-storage-condition
  (storage-condition rt-runtime-error)
  ())

(define-condition rt-stream-error
  (stream-error rt-runtime-error)
  ())

(define-condition rt-file-error
  (file-error rt-stream-error)
  ())

(define-condition rt-cell-error
  (cell-error rt-runtime-error)
  ())

(define-condition rt-unbound-variable
  (unbound-variable rt-cell-error)
  ())

(define-condition rt-undefined-function
  (undefined-function rt-cell-error)
  ())

(define-condition rt-arithmetic-error
  (arithmetic-error rt-runtime-error)
  ())

(define-condition rt-division-by-zero
  (division-by-zero rt-arithmetic-error)
  ())

(define-condition rt-floating-point-overflow
  (floating-point-overflow rt-arithmetic-error)
  ())

(define-condition rt-floating-point-underflow
  (floating-point-underflow rt-arithmetic-error)
  ())

(defvar *rt-debugger-hook*
  nil
  "Runtime debugger hook, called with an unhandled condition before escalation.

The hook receives the condition and must not return a replacement value.  A
dynamic binding shadows this variable for one runtime signal, matching the
scope of the host Common Lisp debugger hook without mutating the host hook.")

(defun rt-invoke-debugger-hook (condition)
  "Invoke the current runtime debugger hook for CONDITION, if any."
  (when *rt-debugger-hook*
    (funcall *rt-debugger-hook* condition))
  condition)

(defun rt-with-debugger-hook (hook thunk)
  "Run THUNK with HOOK installed as the runtime debugger hook."
  (check-type thunk (or function symbol rt-closure-obj))
  (let ((*rt-debugger-hook* hook))
    (rt-call-fn thunk)))

;;; ------------------------------------------------------------
;;; Runtime Condition / Restart Support (FR-300)
;;; ------------------------------------------------------------
(defstruct
    (rt-handler
     (:constructor make-rt-handler (condition-type handler-function)))
  "Runtime condition handler frame."
  condition-type
  handler-function)

(defstruct (rt-restart (:constructor make-rt-restart (name function)))
  "Runtime restart frame."
  name
  function)

(defvar *handler-stack*
  nil
  "Dynamic stack of runtime condition handlers.

The native backend pushes frames here before signaling conditions.  Each frame
contains a condition type and a handler function; the most recent matching
frame is invoked first.")

(defvar *restart-stack*
  nil
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
  (unwind-protect (rt-call-fn thunk)
    (rt-pop-handler)))

(defun rt-find-handler (condition)
  "Return the most recent runtime handler matching CONDITION, or NIL."
  (find-if
   (lambda (handler)
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
  (unwind-protect (rt-call-fn thunk)
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
                   (unwind-protect (run-with-runtime-bindings (rest remaining))
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

(in-package :cl-cc/runtime/conditions)

(define-condition rt-gc-pressure-warning
  (warning rt-runtime-condition)
  ((heap :initarg :heap :reader rt-gc-pressure-warning-heap)
   (occupancy :initarg :occupancy :reader rt-gc-pressure-warning-occupancy)
   (threshold :initarg :threshold :reader rt-gc-pressure-warning-threshold))
  (:report
   (lambda (c s)
     (format s
             "Runtime heap pressure ~,1F% crossed ~D% threshold"
             (rt-gc-pressure-warning-occupancy c)
             (rt-gc-pressure-warning-threshold c)))))

(define-condition rt-oom-condition
  (storage-condition rt-runtime-error)
  ((requested-words :initarg :requested-words :reader rt-oom-requested-words)
   (limit-words :initarg :limit-words :reader rt-oom-limit-words)
   (used-words :initarg :used-words :reader rt-oom-used-words))
  (:report
   (lambda (c s)
     (format s
             "Runtime heap exhausted: requested ~D words, used ~D, limit ~D"
             (rt-oom-requested-words c)
             (rt-oom-used-words c)
             (rt-oom-limit-words c)))))

(define-condition rt-stack-overflow
  (storage-condition rt-runtime-error)
  ((depth :initarg :depth :reader rt-stack-overflow-depth)
   (limit :initarg :limit :reader rt-stack-overflow-limit))
  (:report
   (lambda (c s)
     (format s
             "Runtime stack overflow at depth ~D (limit ~D)"
             (rt-stack-overflow-depth c)
             (rt-stack-overflow-limit c)))))

(defun %rt-signal-stack-overflow-condition (depth limit)
  (error 'rt-stack-overflow :depth depth :limit limit))

(eval-when (:load-toplevel :execute)
  (rt-register-stack-overflow-signaler
   (function %rt-signal-stack-overflow-condition)))

(in-package :cl-cc/runtime/conditions)

(defun rt-signal-error (condition)
  (rt-call-with-condition-signal-guard
   (lambda ()
     (multiple-value-bind (result handled-p) (rt-dispatch-signal condition)
       (if handled-p
           result
           (progn
             (rt-invoke-debugger-hook condition)
             (error condition)))))))

(defun rt-signal (condition)
  (rt-call-with-condition-signal-guard
   (lambda ()
     (multiple-value-bind (result handled-p) (rt-dispatch-signal condition)
       (if handled-p
           result
           (signal condition))))))

(defun rt-warn-fn (condition)
  (rt-call-with-condition-signal-guard
   (lambda ()
     (multiple-value-bind (result handled-p) (rt-dispatch-signal condition)
       (if handled-p
           result
           (warn "~A" condition))))))

(defun rt-cerror (continue-string condition)
  (rt-call-with-condition-signal-guard
   (lambda ()
     (rt-establish-restart 'continue (lambda () nil)
       (lambda ()
         (multiple-value-bind (result handled-p) (rt-dispatch-signal condition)
           (if handled-p
               result
               (cerror continue-string "~A" condition))))))))

(defun rt-invoke-restart (name &rest args)
  (multiple-value-bind (result handled-p) (rt-dispatch-restart name args)
    (if handled-p
        result
        (apply #'invoke-restart name args))))

(defvar *rt-condition-signal-guard* nil)

(defun rt-register-condition-signal-guard (guard)
  (check-type guard function)
  (setf *rt-condition-signal-guard* guard))

(defun rt-call-with-condition-signal-guard (thunk)
  (if *rt-condition-signal-guard*
      (funcall *rt-condition-signal-guard* thunk)
      (funcall thunk)))
