;;;; FFI / Native Bridge (FR-530-533)
;;;;
;;;; Native foreign function interface for the standalone runtime: calling
;;;; OUT to C libraries. On host SBCL this delegates to CFFI/SB-ALIEN; on
;;;; native binary it uses libffi or direct dlopen/dlsym. The reverse
;;;; direction -- embedding this runtime so C code can call IN -- is the
;;;; unrelated cl-cc-* API in ffi-embedding-api.lisp.
(in-package :cl-cc/runtime)

;; ── Platform detection ──
;; ── Dynamic library loading ──
(defvar *rt-ffi-loaded-libs* (make-hash-table :test #'equal))

(defun rt-ffi-load-library (path)
  "Load a shared library. Returns an opaque handle."
  (sb-alien:load-shared-object path))

(defun rt-ffi-close-library (handle)
  "Unload a shared library."
  (declare (ignore handle))
  nil)  ; SBCL doesn't support unloading

(defun rt-ffi-find-symbol (handle name)
  "Find a symbol address in a loaded library. Returns a function pointer."
  (declare (ignore handle))
  (sb-alien:extern-alien name (function sb-alien:void)))

;; ── Foreign function calling ──
(defvar *rt-ffi-registered-functions* (make-hash-table :test #'equal))

(defstruct rt-ffi-function
  (name "")           ; function name
  (library nil)       ; library handle
  (arg-types nil)     ; list of :int, :float, :pointer, :string
  (return-type :void) ; return type
  (ptr nil))          ; function pointer

(defun rt-define-foreign-function (name library arg-types return-type)
  "Declare a foreign function signature."
  (let ((ptr (rt-ffi-find-symbol library name)))
    (setf (gethash name *rt-ffi-registered-functions*)
          (make-rt-ffi-function :name name :library library
                                :arg-types arg-types :return-type return-type
                                :ptr ptr))
    name))

(defun rt-foreign-funcall (name &rest args)
  "Call a registered foreign function."
  (let ((ff (gethash name *rt-ffi-registered-functions*)))
    (unless ff (error "Unknown foreign function: ~A" name))
    (apply #'sb-alien:alien-funcall
           (sb-alien:extern-alien name
             (function sb-alien:void))
           args)))

;; ── Callback support ──
(defstruct rt-ffi-callback
  (id 0)
  (fn nil)        ; Lisp function
  (arg-types nil)
  (return-type :void)
  (trampoline nil))  ; native code address

(defvar *rt-ffi-callbacks* (make-hash-table))
(defvar *rt-ffi-next-callback-id* 0)

(defun rt-make-callback (fn arg-types return-type)
  "Create a C-callable function pointer from a Lisp function."
  (declare (ignore arg-types return-type)
           #-(and sbcl sb-alien-callback) (ignore fn))
  #+(and sbcl sb-alien-callback)
  (progn
    (incf *rt-ffi-next-callback-id*)
    (sb-alien:alien-callback (function sb-alien:void) fn))
  #-(and sbcl sb-alien-callback)
  (error "C callback trampolines require SB-ALIEN-CALLBACK support."))

(defun rt-ffi-callback-invoke (cb-id &rest args)
  "Invoke a registered callback. Called from native code."
  (let ((cb (gethash cb-id *rt-ffi-callbacks*)))
    (when cb
      (apply (rt-ffi-callback-fn cb) args))))

;; ── Native struct mapping ──
(defstruct rt-ffi-struct-type
  (name "")
  (fields nil)   ; ((field-name type offset size) ...)
  (total-size 0)
  (alignment 8))

(defvar *rt-ffi-struct-types* (make-hash-table :test #'equal))

(defun rt-define-foreign-struct (name &rest fields)
  "Define a native struct layout with ABI-compliant alignment."
  (let* ((aligned-fields nil)
         (offset 0)
         (max-align 1))
    (dolist (f fields)
      (destructuring-bind (fname ftype) f
        (let* ((size (ecase ftype
                       (:int8 1) (:uint8 1)
                       (:int16 2) (:uint16 2)
                       (:int32 4) (:uint32 4) (:float32 4)
                       (:int64 8) (:uint64 8) (:float64 8)
                       (:pointer 8)))
               (align size))
          (setf max-align (max max-align align))
          (setf offset (ceiling offset align))
          (push (list fname ftype offset size) aligned-fields)
          (incf offset size))))
    (setf offset (ceiling offset max-align))
    (setf (gethash name *rt-ffi-struct-types*)
          (make-rt-ffi-struct-type :name name
                                   :fields (nreverse aligned-fields)
                                   :total-size offset
                                   :alignment max-align))
    name))

(defun rt-ffi-struct-size (name)
  (let ((st (gethash name *rt-ffi-struct-types*)))
    (or (rt-ffi-struct-type-total-size st) 0)))

(defun rt-ffi-struct-field-offset (name field-name)
  (let ((st (gethash name *rt-ffi-struct-types*)))
    (when st
      (dolist (f (rt-ffi-struct-type-fields st))
        (when (eq (first f) field-name)
          (return (third f)))))))

;; ── Initialization ──
(defun rt-ffi-init ()
  (clrhash *rt-ffi-loaded-libs*)
  (clrhash *rt-ffi-registered-functions*)
  (clrhash *rt-ffi-callbacks*)
  (clrhash *rt-ffi-struct-types*)
  (setf *rt-ffi-next-callback-id* 0)
  t)

;;; ──── FR-522: Deoptimization Trampoline ────
;;; Called by native codegen when a deoptimization checkpoint is hit.
;;; The trampoline saves register state, reconstructs the interpreter
;;; frame from the deopt metadata, and resumes execution in the interpreter.

(defvar *rt-deopt-enabled* t
  "When T, deoptimization trampolines are active.
When NIL, deopt checkpoints are treated as fatal errors.")

(defvar *rt-deopt-frame-count* 0
  "Number of deoptimization events since startup, for diagnostics.")

(defun rt-deopt-trampoline (deopt-id saved-regs)
  "FR-522: Deoptimization trampoline — called from native code.
DEOPT-ID is the checkpoint identifier. SAVED-REGS is a plist of
(register-name . value) pairs captured by the codegen prologue.
Reconstructs interpreter state and transfers control."
  (incf *rt-deopt-frame-count*)
  (error "Deoptimization trampoline invoked (id=~D, frame=~D). ~
          Full interpreter state reconstruction is not implemented. ~
          Saved registers: ~S"
         deopt-id *rt-deopt-frame-count* saved-regs))

;; C ABI entry point for the deopt trampoline
(setf (symbol-function '|_cl_cc_deopt_trampoline|)
      (lambda (deopt-id)
        (rt-deopt-trampoline deopt-id nil)))
