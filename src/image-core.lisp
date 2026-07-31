;;;; image-core.lisp — Binary buffer I/O, RLE compression, and token encoding
;;;; primitives shared by image-core-graph.lisp and image-core-persist.lisp
(in-package :cl-cc/runtime)

(defun %rt-image-make-buffer ()
  (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0))

(defun %rt-image-push-byte (buffer byte)
  (vector-push-extend (logand byte #xff) buffer))

(defun %rt-image-write-u16 (buffer value)
  (when (or (< value 0) (> value #xffff))
    (error "Value does not fit in u16: ~d" value))
  (%rt-image-push-byte buffer (ldb (byte 8 8) value))
  (%rt-image-push-byte buffer (ldb (byte 8 0) value)))

(defun %rt-image-write-u32 (buffer value)
  (when (or (< value 0) (> value #xffffffff))
    (error "Value does not fit in u32: ~d" value))
  (%rt-image-push-byte buffer (ldb (byte 8 24) value))
  (%rt-image-push-byte buffer (ldb (byte 8 16) value))
  (%rt-image-push-byte buffer (ldb (byte 8 8) value))
  (%rt-image-push-byte buffer (ldb (byte 8 0) value)))

(defun %rt-image-write-u8 (buffer value)
  (%rt-image-push-byte buffer value))

(defun %rt-image-read-u16 (bytes offset)
  (values (logior (ash (aref bytes offset) 8)
                  (aref bytes (1+ offset)))
          (+ offset 2)))

(defun %rt-image-read-u32 (bytes offset)
  (values (logior (ash (aref bytes offset) 24)
                  (ash (aref bytes (+ offset 1)) 16)
                  (ash (aref bytes (+ offset 2)) 8)
                  (aref bytes (+ offset 3)))
           (+ offset 4)))

(defun %rt-image-read-u8 (bytes offset)
  (values (aref bytes offset) (1+ offset)))

(defun %rt-image-byte-vector-from-string (string)
  (let ((bytes (%rt-image-make-buffer)))
    (loop for ch across string
          do (%rt-image-push-byte bytes (char-code ch)))
    (coerce bytes '(vector (unsigned-byte 8)))))

(defun %rt-image-string-from-byte-vector (bytes &key (start 0) end)
  (%rt-image-bytes-string bytes :start start :end end))

(defun %rt-core-compression-code (compression)
  (cond
    ((or (null compression) (eq compression :none))
     +rt-core-compression-none+)
    ((or (eq compression t) (eq compression :zlib)
         (string-equal (string compression) "zlib"))
     +rt-core-compression-zlib+)
    ((or (eq compression :gzip) (string-equal (string compression) "gzip"))
     +rt-core-compression-gzip+)
    ((or (eq compression :lz4) (string-equal (string compression) "lz4"))
     +rt-core-compression-lz4+)
    ((or (eq compression :zstd) (string-equal (string compression) "zstd"))
     +rt-core-compression-zstd+)
    (t (error "Unknown core compression: ~S" compression))))

(defun %rt-core-rle-compress (bytes)
  "Tiny deterministic RLE codec used as the portable lz4/zstd stand-in."
  (let ((out (%rt-image-make-buffer))
        (i 0)
        (n (length bytes)))
    (loop while (< i n) do
      (let* ((b (aref bytes i))
             (run 1))
        (loop while (and (< (+ i run) n)
                         (< run 255)
                         (= b (aref bytes (+ i run))))
              do (incf run))
        (if (or (>= run 4) (= b #xff))
            (progn
              (%rt-image-push-byte out #xff)
              (%rt-image-push-byte out run)
              (%rt-image-push-byte out b))
            (dotimes (_ run) (%rt-image-push-byte out b)))
        (incf i run)))
    (coerce out '(vector (unsigned-byte 8)))))

(defun %rt-core-rle-decompress (bytes)
  (let ((out (%rt-image-make-buffer))
        (i 0)
        (n (length bytes)))
    (loop while (< i n) do
      (let ((b (aref bytes i)))
        (if (= b #xff)
            (let ((run (aref bytes (1+ i)))
                  (value (aref bytes (+ i 2))))
              (dotimes (_ run) (%rt-image-push-byte out value))
              (incf i 3))
            (progn
              (%rt-image-push-byte out b)
              (incf i)))))
    (coerce out '(vector (unsigned-byte 8)))))

(defun %rt-core-compress-bytes (bytes compression-code)
  (cond
    ((= compression-code +rt-core-compression-none+) bytes)
    ((= compression-code +rt-core-compression-zlib+) (zlib-compress bytes))
    ((= compression-code +rt-core-compression-gzip+) (gzip-compress bytes))
    ((= compression-code +rt-core-compression-lz4+) (%rt-core-rle-compress bytes))
    ((= compression-code +rt-core-compression-zstd+) (%rt-core-rle-compress bytes))
    (t (error "Unknown core compression code: ~D" compression-code))))

(defun %rt-core-decompress-bytes (bytes compression-code)
  (cond
    ((= compression-code +rt-core-compression-none+) bytes)
    ((= compression-code +rt-core-compression-zlib+) (zlib-decompress bytes))
    ((= compression-code +rt-core-compression-gzip+) (gzip-decompress bytes))
    ((= compression-code +rt-core-compression-lz4+) (%rt-core-rle-decompress bytes))
    ((= compression-code +rt-core-compression-zstd+) (%rt-core-rle-decompress bytes))
    (t (error "Unknown core compression code: ~D" compression-code))))

(defun %rt-core-readable-bytes (form)
  (%rt-image-byte-vector-from-string
   (let ((*print-circle* t)
         (*print-readably* t)
         (*package* (find-package :cl-user)))
     (with-output-to-string (s) (write form :stream s)))))

(defun %rt-core-read-readable-bytes (bytes)
  (let ((*read-eval* nil)
        (*package* (find-package :cl-user)))
    (with-input-from-string (s (%rt-image-string-from-byte-vector bytes))
      (read s))))

(defun %rt-core-symbol-token (symbol)
  (list (and (symbol-package symbol) (package-name (symbol-package symbol)))
        (symbol-name symbol)))

(defun %rt-core-token-symbol (token)
  (destructuring-bind (package-name symbol-name) token
    (if package-name
        (intern symbol-name (or (find-package package-name)
                                (make-package package-name :use nil)))
        (make-symbol symbol-name))))

(defun %rt-core-function-name-token (fn)
  (let ((name (ignore-errors (function-lambda-expression fn))))
    (declare (ignore name))
    (or (loop for package in (list-all-packages)
              thereis (do-symbols (sym package)
                        (when (and (fboundp sym) (eq (symbol-function sym) fn))
                          (return (%rt-core-symbol-token sym)))))
        nil)))

(defun %rt-core-class-slot-names (object)
  (mapcar #'sb-mop:slot-definition-name
          (sb-mop:class-slots (class-of object))))
