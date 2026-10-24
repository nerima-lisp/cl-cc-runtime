;;;; image-core-persist.lisp — Core image file format: package/root state,
;;;; the on-disk payload envelope, and rt-save-core / rt-load-core
(in-package :cl-cc/runtime)

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
