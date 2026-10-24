;;;; packages/runtime/src/runtime.lisp - CL-CC Runtime Library
;;;
;;; This library provides the runtime support for x86-64 native code.
;;; Each function here corresponds to a cl_rt_* assembly symbol called
;;; by the generated machine code via CALL instructions.
;;;
;;; Tagged pointer layout (3-bit tag in bits[2:0]):
;;;   000 (0) = fixnum: integer value in bits[63:3]
;;;   001 (1) = cons: pointer to cons cell
;;;   010 (2) = symbol: pointer to symbol
;;;   011 (3) = function/closure: pointer to function
;;;   100 (4) = character: char-code in bits[63:3]
;;;   101 (5) = array/vector: pointer to array
;;;   110 (6) = string: pointer to string
;;;   111 (7) = other heap object

(in-package :cl-cc/runtime)

;;; ------------------------------------------------------------
;;; Tagged Pointer Constants
;;; ------------------------------------------------------------

(defconstant +tag-fixnum+     0)
(defconstant +rt-tag-cons+    1)
(defconstant +rt-tag-symbol+  2)
(defconstant +rt-tag-function+ 3)
(defconstant +tag-character+  4)
(defconstant +tag-array+      5)
(defconstant +rt-tag-string+  6)
(defconstant +tag-other+      7)

(defun rt-tag-fixnum (n)    (ash n 3))
(defun rt-untag-fixnum (x)  (ash x -3))
(defun rt-tag-bits (x)      (logand x 7))

;;; ------------------------------------------------------------
;;; Multiple Values Buffer
;;; ------------------------------------------------------------

(defvar *rt-values-buffer* nil
  "Thread-local buffer for multiple return values.")

(defun rt-values-clear ()
  (setf *rt-values-buffer* nil))

(defun rt-values-push (val)
  (setf *rt-values-buffer* (append *rt-values-buffer* (list val))))

(defun rt-values-count ()
  (length *rt-values-buffer*))

(defun rt-values-ref (idx)
  (nth idx *rt-values-buffer*))

(defun rt-values-to-list ()
  *rt-values-buffer*)

(defun rt-spread-values (val)
  "If val is a list (from multiple values), spread it; otherwise push single."
  (if (listp val)
      (dolist (v val) (rt-values-push v))
      (rt-values-push val))
  val)

(defun rt-ensure-values (val)
  "Ensure at least one value is in the buffer."
  (when (null *rt-values-buffer*)
    (rt-values-push val))
  val)

;;; ------------------------------------------------------------
;;; Closure Support
;;; ------------------------------------------------------------

(defstruct (rt-closure-obj (:conc-name rt-closure-))
  fn
  env)

(defun rt-make-closure (fn env-list)
  (make-rt-closure-obj :fn fn :env (coerce env-list 'vector)))

(defun rt-closure-ref (closure idx)
  (aref (rt-closure-env closure) idx))

(defun rt-call-fn (fn &rest args)
  (if (rt-closure-obj-p fn)
      (apply (rt-closure-fn fn) args)
      (apply fn args)))

(defun rt-apply-fn (fn args-list)
  (if (rt-closure-obj-p fn)
      (apply (rt-closure-fn fn) args-list)
      (apply fn args-list)))

;; Arrays/Vectors, Arithmetic, Bitwise, Comparisons, and Math rt-* wrappers
;; are in runtime-ops.lisp (loaded next).
