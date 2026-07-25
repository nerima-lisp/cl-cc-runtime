;;;; runtime-pathnames.lisp — Native bignum arithmetic, pathnames, compound streams, LOAD
(in-package :cl-cc/runtime)

;;; ─── Native Bignum Support (ANSI CL Ch.12 Number Tower) ────────────────────
;;;
;;; The native codegen calls these runtime helpers when integer arithmetic
;;; overflows fixnum range.  Bignums are represented as tagged cons cells
;;; (:bignum . cl-integer).  The codegen fast path handles fixnum arithmetic
;;; inline; these functions handle the slow path (overflow / mixed types).

(declaim (inline rt-native-bignum-p))

(defun rt-native-bignum-allocate (n)
  "Allocate a bignum value wrapping the CL integer N."
  (cons :bignum n))

(defun rt-native-bignum-p (value)
  "Return T when VALUE is a bignum."
  (and (consp value) (eq (car value) :bignum)))

(defun rt-native-bignum-to-integer (value)
  "Convert a fixed-size (fixnum or bignum) VALUE to a CL integer."
  (if (rt-native-bignum-p value)
      (cdr value)
      (decode-fixnum value)))

(defun rt-native-integer->value (n)
  "Box a CL integer N into the runtime value representation.
  Returns an encoded fixnum when N fits in 51-bit signed range;
  otherwise returns a bignum."
  (if (and (>= n #.(- (ash 1 50)))
           (<= n #.(1- (ash 1 50))))
      (encode-fixnum n)
      (rt-native-bignum-allocate n)))

(defun rt-native-bignum-add (a b)
  "Add two fixed-size integer values A and B.  Returns fixnum when possible."
  (rt-native-integer->value
   (+ (rt-native-bignum-to-integer a) (rt-native-bignum-to-integer b))))

(defun rt-native-bignum-sub (a b)
  "Subtract B from A.  Returns fixnum when possible."
  (rt-native-integer->value
   (- (rt-native-bignum-to-integer a) (rt-native-bignum-to-integer b))))

(defun rt-native-bignum-mul (a b)
  "Multiply A and B.  Returns fixnum when possible."
  (rt-native-integer->value
   (* (rt-native-bignum-to-integer a) (rt-native-bignum-to-integer b))))

;;; ─── Pathname and File System Operations (Wave 4) ──────────────────────────

(defun rt-make-pathname (&key host device directory name type version defaults case)
  (declare (ignore host device version case))
  (let ((p (if defaults
                (merge-pathnames (make-pathname :directory directory :name name :type type) defaults)
                (make-pathname :directory directory :name name :type type))))
    p))

(defun rt-make-pathname-native (host device directory name type version defaults)
  "Native-callable positional-arg version of make-pathname.  All args may be NIL.
   Calls CL:MAKE-PATHNAME with only non-NIL keyword arguments."
  (let ((args nil))
    ;; Accumulate a flat keyword plist; APPLY spreads it as :KEY VALUE pairs.
    ;; (Pushing (cons :key val) instead would spread each cons as a single
    ;; positional argument and signal an odd-&KEY-arguments error.)
    (when version (setf args (list* :version version args)))
    (when type (setf args (list* :type type args)))
    (when name (setf args (list* :name name args)))
    (when directory (setf args (list* :directory directory args)))
    (when device (setf args (list* :device device args)))
    (when host (setf args (list* :host host args)))
    (let ((p (apply #'make-pathname args)))
      (if defaults
          (merge-pathnames p defaults)
          p))))

(defun rt-merge-pathnames (pathname &optional defaults)
  (merge-pathnames pathname (or defaults *default-pathname-defaults*)))

(defun rt-namestring (pathname)
  (namestring pathname))

(defun rt-pathname-name (pathname)
  (pathname-name pathname))

(defun rt-pathname-type (pathname)
  (pathname-type pathname))

(defun rt-pathname-directory (pathname)
  (pathname-directory pathname))

(defun rt-pathnamep (object)
  (pathnamep object))

(defun rt-probe-file (pathname)
  (probe-file pathname))

(defun rt-delete-file (pathname)
  (delete-file pathname))

(defun rt-rename-file (file new-name)
  (rename-file file new-name))

(defun rt-file-write-date (pathname)
  (file-write-date pathname))

(defun rt-directory (pathname &key)
  (directory pathname))

(defun rt-ensure-directories-exist (pathname &key verbose)
  (ensure-directories-exist pathname :verbose verbose))

(defun rt-truename (pathname)
  (truename pathname))

;;; ─── Compound Streams ───────────────────────────────────────────────────────

(defun rt-make-broadcast-stream (&rest streams)
  (apply #'make-broadcast-stream streams))

(defun rt-make-concatenated-stream (&rest streams)
  (apply #'make-concatenated-stream streams))

(defun rt-make-echo-stream (input-stream output-stream)
  (make-echo-stream input-stream output-stream))

(defun rt-make-two-way-stream (input-stream output-stream)
  (make-two-way-stream input-stream output-stream))

(defun rt-make-synonym-stream (symbol)
  (make-synonym-stream symbol))

;;; ─── Sequence I/O ───────────────────────────────────────────────────────────

(defun rt-read-sequence (sequence stream &key start end)
  (read-sequence sequence stream :start (or start 0) :end (or end (length sequence))))

(defun rt-write-sequence (sequence stream &key start end)
  (write-sequence sequence stream :start (or start 0) :end (or end (length sequence))))

;;; ─── LOAD ───────────────────────────────────────────────────────────────────

(defun rt-load (pathname &key verbose print if-does-not-exist external-format)
  (declare (ignore verbose print if-does-not-exist external-format))
  (load pathname))

;;; ─── JIT-Callable Bignum Bridges (for native codegen slow path) ────────────

(sb-alien:define-alien-callable cl_cc_bignum_add
    sb-alien:long
    ((a sb-alien:long) (b sb-alien:long))
  (rt-native-bignum-add a b))

(sb-alien:define-alien-callable cl_cc_bignum_sub
    sb-alien:long
    ((a sb-alien:long) (b sb-alien:long))
  (rt-native-bignum-sub a b))

(sb-alien:define-alien-callable cl_cc_bignum_mul
    sb-alien:long
    ((a sb-alien:long) (b sb-alien:long))
  (rt-native-bignum-mul a b))
