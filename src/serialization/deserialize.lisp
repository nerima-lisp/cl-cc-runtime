;;;; deserialize.lisp — Deserialization (read) path, ending in DESERIALIZE,
;;;; split out of serialize.lisp. Uses the wire-format tags and low-level
;;;; byte/integer readers serialize.lisp defines.
(in-package :cl-cc/runtime)

(defun %read-string (ctx source)
  (%remember-read-object (%read-raw-string source) ctx))

(defun %read-symbol (source)
  (%read-raw-symbol source))

(defun %read-character (source)
  (code-char (%read-unsigned-integer source)))

(defun %read-cons (ctx source)
  (let ((cell (cons nil nil)))
    (%remember-read-object cell ctx)
    (setf (car cell) (%read-object ctx source)
          (cdr cell) (%read-object ctx source))
    cell))

(defun %read-vector (ctx source)
  (let* ((length (%read-unsigned-integer source))
         (vector (make-array length)))
    (%remember-read-object vector ctx)
    (dotimes (index length vector)
      (setf (aref vector index) (%read-object ctx source)))))

(defun %read-hash-table (ctx source)
  (let* ((count (%read-unsigned-integer source))
         (table (make-hash-table :test #'equal :size count)))
    (%remember-read-object table ctx)
    (dotimes (index count table)
      (setf (gethash (%read-object ctx source) table)
            (%read-object ctx source)))))

(defun %read-standard-object (ctx source)
  (let* ((class-name (%read-raw-symbol source))
         (class (find-class class-name))
         (object (allocate-instance class))
         (slot-count (%read-unsigned-integer source)))
    (%remember-read-object object ctx)
    (dotimes (index slot-count object)
      (let ((slot-name (%read-raw-symbol source)))
        (setf (slot-value object slot-name)
              (%read-object ctx source))))))

(defun %read-reference (ctx source)
  (let* ((id (%read-object ctx source))
         (object (gethash id (ser-ctx-read ctx) :missing)))
    (when (eq object :missing)
      (%serialization-error "unknown reference id ~D" id))
    object))

(defun %read-object (ctx source)
  (let ((tag (%read-byte* source)))
    (case tag
      (#.+ser-tag-nil+ nil)
      (#.+ser-tag-t+ t)
      (#.+ser-tag-integer+ (%read-signed-integer-payload source))
      (#.+ser-tag-float+ (%read-float source))
      (#.+ser-tag-character+ (%read-character source))
      (#.+ser-tag-string+ (%read-string ctx source))
      (#.+ser-tag-symbol+ (%read-symbol source))
      (#.+ser-tag-cons+ (%read-cons ctx source))
      (#.+ser-tag-vector+ (%read-vector ctx source))
      (#.+ser-tag-hash-table+ (%read-hash-table ctx source))
      (#.+ser-tag-standard-object+ (%read-standard-object ctx source))
      (#.+ser-tag-reference+ (%read-reference ctx source))
      (otherwise (%serialization-error "unknown tag ~D" tag)))))

(defun %deserialize-source (source)
  (etypecase source
    (stream source)
    (vector (make-ser-reader source))))

(defun deserialize (source)
  "Deserialize an object from SOURCE, a byte vector or binary stream."
  (%read-object (make-ser-ctx) (%deserialize-source source)))
