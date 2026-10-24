;;;; Core Image Save/Restore (FR-350, FR-352)
(in-package :cl-cc/runtime)

(defconstant +image-magic+ #x434C4343)
(defconstant +rt-image-version+ 1)
(defconstant +rt-image-format+ :cl-cc-runtime-image)
(defconstant +rt-image-crc32-polynomial+ #xedb88320)

(defconstant +rt-core-version+ 1)
(defconstant +rt-core-segment-code+ 1)
(defconstant +rt-core-segment-data+ 2)
(defconstant +rt-core-segment-symbols+ 3)
(defconstant +rt-core-compression-none+ 0)
(defconstant +rt-core-compression-zlib+ 1)
(defconstant +rt-core-compression-gzip+ 2)
(defconstant +rt-core-compression-lz4+ 3)
(defconstant +rt-core-compression-zstd+ 4)

(defconstant +rt-image-value-nil+ 0)
(defconstant +rt-image-value-fixnum+ 1)
(defconstant +rt-image-value-string+ 2)
(defconstant +rt-image-value-symbol-ref+ 3)
(defconstant +rt-image-value-function-code+ 4)
(defconstant +rt-image-value-cons+ 5)

(defstruct rt-image-header
  (magic +image-magic+ :type integer)
  (version +rt-image-version+ :type integer)
  (format +rt-image-format+)
  (created-at 0 :type integer))

(defstruct rt-image
  (header (make-rt-image-header))
  (globals nil)
  (heap nil)
  (code-version 0 :type integer))

(defvar *rt-image-globals* nil)
(defvar *rt-image-restore-hooks* nil)
(defvar *rt-code-version* 0)
(defvar *saved-core-pathname* nil
  "Pathname of the most recently loaded CL-CC core file.")
(defvar *rt-loaded-core* nil
  "Descriptor plist for the most recently loaded native CL-CC core.")
(defvar *rt-core-function-registry* (make-hash-table :test #'equal)
  "Best-effort host closure registry used when save/load occurs in one host image.")

(defun rt-image-register-global (sym)
  (check-type sym symbol)
  (pushnew sym *rt-image-globals* :test #'eq)
  sym)

(defun rt-image-register-restore-hook (fn)
  (check-type fn function)
  (pushnew fn *rt-image-restore-hooks*)
  fn)

(defun %rt-global-pair (sym)
  (list sym (when (boundp sym) (symbol-value sym))))

(defun rt-capture-image-state (&key globals heap)
  (let ((symbols (or globals *rt-image-globals*)))
    (make-rt-image
     :header (make-rt-image-header :created-at (get-universal-time))
     :globals (mapcar #'%rt-global-pair symbols)
     :heap heap
     :code-version *rt-code-version*)))

(defun rt-validate-image (image)
  (unless (typep image 'rt-image) (error "Not a runtime image: ~s" image))
  (let ((header (rt-image-header image)))
    (unless (= (rt-image-header-magic header) +image-magic+)
      (error "Bad image magic: ~x" (rt-image-header-magic header)))
    (unless (= (rt-image-header-version header) +rt-image-version+)
      (error "Bad image version: ~d" (rt-image-header-version header))))
  t)
