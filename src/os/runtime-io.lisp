(in-package :cl-cc/runtime)

;;; ------------------------------------------------------------
;;; I/O
;;; ------------------------------------------------------------

;;; Macro for optional-stream I/O: (rt-foo args... &optional stream)
;;; delegates to (cl-fn args... stream) or (cl-fn args...) for default stream.
(defmacro define-rt-stream-op (rt-name cl-name (&rest fixed-args))
  (list 'defun rt-name
        (append fixed-args '(&optional stream))
        (list 'if 'stream
              (cons cl-name (append fixed-args '(stream)))
              (cons cl-name fixed-args))))

(defun rt-print (x) (print x))
(defun rt-princ (x) (princ x))
(defun rt-prin1 (x) (prin1 x))
(defun rt-terpri () (terpri))
(defun rt-fresh-line () (fresh-line))
(define-rt-stream-op rt-write-char   write-char   (c))
(define-rt-stream-op rt-write-string write-string (s))
(define-rt-stream-op rt-write-line   write-line   (s))
(define-rt-stream-op rt-unread-char  unread-char  (c))
(define-rt-stream-op rt-read-char    read-char    ())
(define-rt-stream-op rt-read-line    read-line    ())
(define-rt-stream-op rt-finish-output finish-output ())
(define-rt-stream-op rt-force-output  force-output  ())
(define-rt-stream-op rt-clear-output  clear-output  ())
(defun rt-write-to-string (obj)
  "Native-callable simple write-to-string. Uses current CL print-control variables."
  (write-to-string obj))

(defun rt-write-to-string-with-controls (obj &key base radix escape level length
                                                  circle pretty case readably
                                                  gensym array)
  "Native-callable write-to-string with full ANSI print-control keyword support."
  (let ((*print-base*   (or base *print-base*))
        (*print-radix*  (or radix *print-radix*))
        (*print-escape* (if (eq escape nil) nil t))
        (*print-level*  level)
        (*print-length* length)
        (*print-circle* (or circle *print-circle*))
        (*print-pretty* (or pretty *print-pretty*))
        (*print-case*   (or case *print-case*))
        (*print-readably* (or readably *print-readably*))
        (*print-gensym* (or gensym *print-gensym*))
        (*print-array*  (or array *print-array*)))
    (write-to-string obj)))

(defun rt-write-byte (byte &optional stream)
  (if stream (write-byte byte stream) (write-byte byte *standard-output*)))
(defun rt-format (stream fmt &rest args)
  (apply #'format stream fmt args))
(defun rt-read-byte (&optional stream)
  (if stream (read-byte stream) (read-byte *standard-input*)))
(defun rt-peek-char (&optional stream)
  (if stream (peek-char nil stream nil nil) (peek-char nil *standard-input* nil nil)))
(defun rt-open-file (path &key (direction :input) if-exists)
  (open path :direction direction :if-exists (or if-exists :supersede)))
(defun rt-close-file (stream) (close stream))
(defun rt-make-string-stream (s &key (direction :input))
  (if (eq direction :input)
      (make-string-input-stream s)
      (make-string-output-stream)))
(defun rt-make-string-output-stream () (make-string-output-stream))
(defun rt-get-output-stream-string (stream) (get-output-stream-string stream))
(defun rt-stream-write-string (stream s) (write-string s stream))
(define-rt-predicate rt-input-stream-p       input-stream-p)
(define-rt-predicate rt-output-stream-p      output-stream-p)
(define-rt-predicate rt-open-stream-p        open-stream-p)
(define-rt-predicate rt-interactive-stream-p interactive-stream-p)
(defun rt-stream-element-type (s) (stream-element-type s))
