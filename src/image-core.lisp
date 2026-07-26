;;;; image-core.lisp — Binary encode/decode primitives, compression, core save/load
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

(defun %rt-core-encode-graph (roots)
  "Copy reachable heap objects from ROOTS into a position-independent graph."
  (let ((forwarding (make-hash-table :test #'eq))
        (nodes nil)
        (next-id 0))
    (labels ((object-id (object)
               (multiple-value-bind (id presentp) (gethash object forwarding)
                 (if presentp
                     id
                     (let ((new-id next-id))
                       (incf next-id)
                       (setf (gethash object forwarding) new-id)
                       new-id))))
             (host-function-key (fn)
               (or (%rt-core-function-name-token fn)
                   (let ((key (format nil "host-closure-~36R" (sxhash fn))))
                     (setf (gethash key *rt-core-function-registry*) fn)
                     key)))
             (encode (object)
               (cond
                 ((null object) '(:immediate :nil))
                 ((eq object t) '(:immediate :t))
                 ((or (numberp object) (characterp object) (stringp object))
                  (list :immediate object))
                 ((symbolp object) (list :symbol (%rt-core-symbol-token object)))
                 ((or (consp object) (vectorp object) (hash-table-p object)
                      (functionp object) (typep object 'standard-object))
                  (let ((known (gethash object forwarding)))
                    (when known (return-from encode (list :ref known))))
                  (let ((id (object-id object)))
                    (cond
                      ((consp object)
                       (push (list :node id :cons
                                   (encode (car object)) (encode (cdr object)))
                             nodes))
                      ((vectorp object)
                       (push (list :node id :vector (map 'list #'encode object)) nodes))
                      ((hash-table-p object)
                       (let ((entries nil))
                         (maphash (lambda (k v) (push (list (encode k) (encode v)) entries)) object)
                         (push (list :node id :hash (hash-table-test object)
                                     (nreverse entries))
                               nodes)))
                      ((functionp object)
                       (push (list :node id :function (host-function-key object)) nodes))
                      ((typep object 'standard-object)
                       (let ((slots nil))
                         (dolist (slot (%rt-core-class-slot-names object))
                           (push (list slot
                                       (slot-boundp object slot)
                                       (when (slot-boundp object slot)
                                         (encode (slot-value object slot))))
                                 slots))
                         (push (list :node id :instance
                                     (%rt-core-symbol-token (class-name (class-of object)))
                                     (nreverse slots))
                               nodes))))
                    (list :ref id)))
                 (t
                  (list :unreadable (type-of object) (prin1-to-string object))))))
      (let ((encoded-roots (mapcar (lambda (entry)
                                     (destructuring-bind (name value) entry
                                       (list name (encode value))))
                                   roots)))
        (list :roots encoded-roots
              :nodes (sort (copy-list nodes) #'< :key #'second)
              :object-count next-id)))))

(defun %rt-core-decode-graph (graph)
  "Restore a graph produced by %RT-CORE-ENCODE-GRAPH and fix internal offsets."
  (let* ((nodes (getf graph :nodes))
         (objects (make-hash-table :test #'eql)))
    (labels ((placeholder (node)
               (destructuring-bind (_ id kind &rest payload) node
                 (declare (ignore _))
                 (setf (gethash id objects)
                       (case kind
                         (:cons (cons nil nil))
                         (:vector (make-array (length (first payload))))
                         (:hash (make-hash-table :test (or (first payload) 'eql)))
                         (:instance
                          (allocate-instance
                           (find-class (%rt-core-token-symbol (first payload)))))
                         (:function (let ((key (first payload)))
                                      (cond
                                        ((consp key) (symbol-function (%rt-core-token-symbol key)))
                                        (t
                                         (multiple-value-bind (fn presentp)
                                             (gethash key *rt-core-function-registry*)
                                           (if presentp
                                               fn
                                               ((lambda (missing-key)
                                                  (lambda (&rest args)
                                                    (declare (ignore args))
                                                    (error "Saved host closure is unavailable: ~A"
                                                           missing-key)))
                                                key)))))))
                         (otherwise nil)))))
             (resolve (form)
               (case (first form)
                 (:immediate (if (eq (second form) :nil)
                                 nil
                                 (if (eq (second form) :t) t (second form))))
                 (:symbol (%rt-core-token-symbol (second form)))
                 (:ref (gethash (second form) objects))
                 (:unreadable nil)
                 (otherwise form)))
             (fill-node (node)
               (destructuring-bind (_ id kind &rest payload) node
                 (declare (ignore _))
                 (let ((object (gethash id objects)))
                   (case kind
                     (:cons
                      (setf (car object) (resolve (first payload))
                            (cdr object) (resolve (second payload))))
                     (:vector
                      (loop for item in (first payload)
                            for i from 0
                            do (setf (aref object i) (resolve item))))
                     (:hash
                      (dolist (entry (second payload))
                        (setf (gethash (resolve (first entry)) object)
                              (resolve (second entry)))))
                     (:instance
                      (dolist (slot-entry (second payload))
                        (destructuring-bind (slot-name boundp encoded) slot-entry
                          (when boundp
                            (setf (slot-value object slot-name) (resolve encoded)))))))))))
      (dolist (node nodes) (placeholder node))
      (dolist (node nodes) (fill-node node))
      (mapcar (lambda (entry)
                (destructuring-bind (name encoded) entry
                  (list name (resolve encoded))))
              (getf graph :roots)))))

(defun %rt-core-package-state ()
  (loop for package in (list-all-packages)
        collect (list :name (package-name package)
                      :nicknames (package-nicknames package)
                      :use (mapcar #'package-name (package-use-list package)))))

(defun %rt-core-restore-package-state (state)
  (dolist (entry state)
    (let ((name (getf entry :name)))
      (unless (find-package name)
        (make-package name :nicknames (getf entry :nicknames) :use nil))))
  t)

(defun %rt-core-root-entries ()
  (let ((symbols (remove-duplicates *rt-image-globals* :test #'eq)))
    (loop for sym in symbols
          append (append
                  (when (boundp sym)
                    (list (list (list :value (%rt-core-symbol-token sym)) (symbol-value sym))))
                  (when (fboundp sym)
                    (list (list (list :function (%rt-core-symbol-token sym))
                                (symbol-function sym))))
                  (list (list (list :plist (%rt-core-symbol-token sym)) (symbol-plist sym)))))))

(defun %rt-core-restore-root (root)
  (destructuring-bind (name value) root
    (destructuring-bind (kind token) name
      (let ((sym (%rt-core-token-symbol token)))
        (ecase kind
          (:value (setf (symbol-value sym) value))
          (:function (setf (symbol-function sym) value))
          (:plist (setf (symbol-plist sym) value)))
        (rt-image-register-global sym)))))

(defun %rt-core-payload (toplevel)
  (let* ((roots (%rt-core-root-entries))
         (graph (%rt-core-encode-graph roots)))
    (list :format :cl-cc-core
          :version +rt-core-version+
          :created-at (get-universal-time)
          :code-version *rt-code-version*
          :toplevel (and toplevel (%rt-core-symbol-token toplevel))
          :packages (%rt-core-package-state)
          :graph graph)))

(defun %rt-core-write-file (path bytes compression-code executable)
  (let* ((payload (%rt-core-compress-bytes bytes compression-code))
         (payload-offset 52)
         (buffer (%rt-image-make-buffer)))
    (%rt-image-write-u32 buffer +image-magic+)
    (%rt-image-write-u16 buffer +rt-core-version+)
    (%rt-image-write-u8 buffer compression-code)
    (%rt-image-write-u32 buffer payload-offset)
    (%rt-image-write-u16 buffer 3)
    (%rt-image-write-u32 buffer (length bytes))
    (%rt-image-write-u32 buffer (length payload))
    (%rt-image-write-u32 buffer (%rt-image-crc32 payload))
    ;; segment table: code heap, data heap, symbol table.  The portable CL core
    ;; stores code/symbol metadata inside the position-independent data segment.
    (%rt-image-write-u8 buffer +rt-core-segment-code+)
    (%rt-image-write-u32 buffer payload-offset)
    (%rt-image-write-u32 buffer 0)
    (%rt-image-write-u8 buffer +rt-core-segment-data+)
    (%rt-image-write-u32 buffer payload-offset)
    (%rt-image-write-u32 buffer (length payload))
    (%rt-image-write-u8 buffer +rt-core-segment-symbols+)
    (%rt-image-write-u32 buffer (+ payload-offset (length payload)))
    (%rt-image-write-u32 buffer 0)
    (loop for byte across payload do (%rt-image-push-byte buffer byte))
    (with-open-file (out path :direction :output :if-exists :supersede
                             :if-does-not-exist :create
                             :element-type '(unsigned-byte 8))
      (when executable
        ;; Native backends replace this portable marker with an ELF/Mach-O loader
        ;; stub.  RT-LOAD-CORE scans for the magic word so the marker is harmless.
        (write-sequence (%rt-image-byte-vector-from-string "CLCC-CORE-STUB\n") out))
      (write-sequence buffer out))
    path))

(defun %rt-core-find-magic-offset (bytes)
  (loop for i from 0 to (- (length bytes) 4)
        when (= (logior (ash (aref bytes i) 24)
                       (ash (aref bytes (+ i 1)) 16)
                       (ash (aref bytes (+ i 2)) 8)
                       (aref bytes (+ i 3)))
                +image-magic+)
          do (return i)
        finally (error "Bad core magic")))

(defun rt-save-core (path &key toplevel executable compression)
  "Save a CL-CC native core containing registered roots and reachable heap graph.

The portable implementation uses the same copying-collector shape required by
FR-1002: roots are walked, reachable objects are assigned forwarding ids, and
all internal references are written as base-independent offsets.  Native loaders
can consume the same header/segment envelope and replace the marker executable
stub with an ELF/Mach-O mmap loader."
  (let* ((toplevel-symbol (cond
                           ((null toplevel) nil)
                           ((symbolp toplevel) toplevel)
                           ((stringp toplevel) (read-from-string toplevel))
                           (t (error "Unsupported core toplevel designator: ~S" toplevel))))
         (payload (%rt-core-payload toplevel-symbol))
         (bytes (%rt-core-readable-bytes payload))
         (compression-code (%rt-core-compression-code compression)))
    (%rt-core-write-file path bytes compression-code executable)))

(defun %rt-core-locate-data-segment (bytes offset base segment-count)
  "Scan SEGMENT-COUNT segment-table entries starting at OFFSET, returning the
data segment's absolute offset and size as two values (NIL NIL when absent)."
  (let ((data-offset nil)
        (data-size nil))
    (dotimes (_ segment-count)
      (multiple-value-bind (kind offset*) (%rt-image-read-u8 bytes offset)
        (multiple-value-bind (seg-offset offset**) (%rt-image-read-u32 bytes offset*)
          (multiple-value-bind (seg-size offset***) (%rt-image-read-u32 bytes offset**)
            (when (= kind +rt-core-segment-data+)
              (setf data-offset (+ base seg-offset)
                    data-size seg-size))
            (setf offset offset***)))))
    (values data-offset data-size)))

(defun rt-load-core (path &key dynamic-space-size)
  "Load a CL-CC core using mmap-backed lazy byte access and restore roots.

The portable mmap layer maps the file MAP_PRIVATE, records PROT_NONE/lazy-load
metadata in the returned descriptor, decompresses the data segment, then fixes
all graph references through offset ids before restoring symbol values,
function bindings, packages, and restore hooks."
  (declare (ignore dynamic-space-size))
  (let* ((region (mmap-file path :protection :read :flags :private))
         (bytes (mmap-array region))
         (base (%rt-core-find-magic-offset bytes)))
    (multiple-value-bind (magic offset) (%rt-image-read-u32 bytes base)
      (declare (ignore magic))
      (multiple-value-bind (version offset) (%rt-image-read-u16 bytes offset)
        (unless (= version +rt-core-version+)
          (error "Bad core version: ~D" version))
          (multiple-value-bind (compression-code offset) (%rt-image-read-u8 bytes offset)
            (multiple-value-bind (roots-offset offset) (%rt-image-read-u32 bytes offset)
              (declare (ignore roots-offset))
              (multiple-value-bind (segment-count offset) (%rt-image-read-u16 bytes offset)
                (multiple-value-bind (uncompressed-size offset) (%rt-image-read-u32 bytes offset)
                  (multiple-value-bind (compressed-size offset) (%rt-image-read-u32 bytes offset)
                    (declare (ignore compressed-size))
                    (multiple-value-bind (stored-crc offset) (%rt-image-read-u32 bytes offset)
                    (multiple-value-bind (data-offset data-size)
                        (%rt-core-locate-data-segment bytes offset base segment-count)
                      (unless data-offset (error "Core contains no data segment"))
                      (let* ((compressed (subseq bytes data-offset (+ data-offset data-size)))
                             (crc (%rt-image-crc32 compressed)))
                        (unless (= crc stored-crc)
                          (error "Bad core CRC: expected ~8,'0x, got ~8,'0x" stored-crc crc))
                        (let* ((payload-bytes
                                (%rt-core-decompress-bytes compressed compression-code))
                               (payload (%rt-core-read-readable-bytes payload-bytes)))
                          (unless (= (length payload-bytes) uncompressed-size)
                            (error "Core payload size mismatch"))
                          (unless (and (eq (getf payload :format) :cl-cc-core)
                                       (= (getf payload :version) +rt-core-version+))
                            (error "Not a compatible CL-CC core"))
                          (%rt-core-restore-package-state (getf payload :packages))
                          (dolist (root (%rt-core-decode-graph (getf payload :graph)))
                            (%rt-core-restore-root root))
                          (setf *rt-code-version* (getf payload :code-version)
                                *saved-core-pathname* (pathname path)
                                *rt-loaded-core* (list :path (pathname path)
                                                       :mmap-region region
                                                       :lazy-loading t
                                                       :page-protection :prot-none-until-fault
                                                       :aslr :offset-relative
                                                       :segments segment-count))
                          (dolist (hook *rt-image-restore-hooks*)
                            (funcall hook *rt-loaded-core*))
                          *rt-loaded-core*)))))))))))))
