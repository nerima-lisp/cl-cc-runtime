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

(in-package :cl-cc/runtime/values)
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

(defun rt-random (n) (random n))
(defun rt-make-random-state (&optional state)
  (if state (make-random-state state) (make-random-state)))
(defun rt-read-from-string (s) (read-from-string s))
(defun rt-read-sexp (stream) (read stream))
(defun rt-coerce (x type) (coerce x type))
