;;;; packages/runtime/src/runtime-math-io.lisp - CL-CC Runtime: symbol plists,
;;;; variadic arithmetic/comparison wrappers, condition signaling, and misc
;;;; time/random/read primitives. Weak hash tables are in
;;;; runtime-weak-hash-table.lisp; special-variable dynamic binding is in
;;;; runtime-dynamic-binding.lisp.
;;;
;;; Contains: rt-symbol-*, rt-intern, rt-make-hash-table,
;;; rt-gethash/sethash/remhash/clrhash/maphash,
;;;            rt-hash-count/test/size/rehash-size/rehash-threshold,
;;; rt-signal-error, rt-signal, rt-warn-fn, rt-cerror, rt-boundp/fboundp,
;;; rt-random, rt-coerce, rt-read-from-string, rt-read-sexp.
;;;
;;; Strings/characters are in runtime-strings.lisp; CLOS/generic dispatch in runtime-clos.lisp.
;;; Depends on runtime.lisp. Load order: after runtime-ops.lisp.

(in-package :cl-cc/runtime)
(defun rt-symbol-plist (sym) (symbol-plist sym))
(defun rt-get-prop (sym indicator) (get sym indicator))
(defun rt-put-prop (sym indicator val) (setf (get sym indicator) val))
(defun rt-remprop (sym indicator) (remprop sym indicator))

;;; ------------------------------------------------------------
;;; Pure scalar/sequence helpers used by the VM bridge
;;; ------------------------------------------------------------

(defun rt-1+ (x) (1+ x))
(defun rt-1- (x) (1- x))
(defun rt-+ (&rest xs) (apply #'+ xs))
(defun rt-- (&rest xs) (apply #'- xs))
(defun rt-* (&rest xs) (apply #'* xs))
(defun rt-/ (&rest xs) (apply #'/ xs))
(defun rt-< (&rest xs) (apply #'< xs))
(defun rt-> (&rest xs) (apply #'> xs))
(defun rt-<= (&rest xs) (apply #'<= xs))
(defun rt->= (&rest xs) (apply #'>= xs))
(defun rt-max (&rest xs) (apply #'max xs))
(defun rt-min (&rest xs) (apply #'min xs))
(defun rt-length (x) (length x))
(defun rt-char= (&rest xs) (apply #'char= xs))
(defun rt-char-equal (&rest xs) (apply #'char-equal xs))
(defun rt-equalp (a b) (equalp a b))
(defun rt-elt (sequence index) (elt sequence index))
(defun rt-append (&rest lists) (apply #'append lists))

;;; ------------------------------------------------------------
;;; Conditions / Error Handling
;;; ------------------------------------------------------------

(defun %rt-current-signal-heap ()
  (and (boundp '*rt-current-gc-heap*)
       *rt-current-gc-heap*))

(defmacro %rt-with-signal-gc-inhibit (&body body)
  "Run BODY while runtime signal handling temporarily inhibits GC when possible."
  (let ((heap (gensym "HEAP"))
        (old (gensym "OLD-INHIBIT")))
    `(let* ((,heap (%rt-current-signal-heap))
            (,old (and ,heap (rt-heap-gc-inhibit ,heap))))
       (unwind-protect
            (progn
              (when (and ,heap (fboundp 'rt-gc-signal-handler-enter))
                (rt-gc-signal-handler-enter ,heap))
              ,@body)
         (when (and ,heap (fboundp 'rt-gc-signal-handler-leave))
           (rt-gc-signal-handler-leave ,heap ,old))))))

(defun rt-signal-error (condition)
  (%rt-with-signal-gc-inhibit
    (multiple-value-bind (result handled-p) (rt-dispatch-signal condition)
      (if handled-p
          result
          (error condition)))))

(defun rt-signal (condition)
  (%rt-with-signal-gc-inhibit
    (multiple-value-bind (result handled-p) (rt-dispatch-signal condition)
      (if handled-p
          result
          (signal condition)))))

(defun rt-warn-fn (condition)
  (%rt-with-signal-gc-inhibit
    (multiple-value-bind (result handled-p) (rt-dispatch-signal condition)
      (if handled-p
          result
          (warn "~A" condition)))))

(defun rt-cerror (continue-string condition)
  (%rt-with-signal-gc-inhibit
    (rt-establish-restart 'continue (lambda () nil)
      (lambda ()
        (multiple-value-bind (result handled-p) (rt-dispatch-signal condition)
          (if handled-p
              result
              (cerror continue-string "~A" condition)))))))

(defun rt-invoke-restart (name &rest args)
  (multiple-value-bind (result handled-p) (rt-dispatch-restart name args)
    (if handled-p
        result
        (apply #'invoke-restart name args))))

;;; ------------------------------------------------------------
;;; Misc
;;; ------------------------------------------------------------

(defun rt-boundp (sym)
  (if (nth-value 1 (gethash sym *rt-global-var-registry*)) 1 0))

(defun rt-makunbound (sym)
  (remhash sym *rt-global-var-registry*)
  sym)
(defun rt-random (n) (random n))
(defun rt-make-random-state (&optional state)
  (if state (make-random-state state) (make-random-state)))
(defun rt-get-universal-time () (get-universal-time))
(defun rt-get-internal-real-time () (get-internal-real-time))
(defun rt-get-internal-run-time () (get-internal-run-time))
(defun rt-read-from-string (s) (read-from-string s))
(defun rt-read-sexp (stream) (read stream))
(defun rt-coerce (x type) (coerce x type))
