(in-package :cl-cc/runtime/memory)

  (defparameter +rt-page-size+ 4096)

(defconstant +rt-prot-none+ 0)

(defconstant +rt-prot-read+ 1)

(defconstant +rt-prot-write+ 2)

(defconstant +rt-prot-exec+ 4)

(defconstant +rt-map-shared+ 1)

(defconstant +rt-map-private+ 2)

(defconstant +rt-map-fixed+ 16)

(defparameter +rt-map-anonymous+ 0)

(defstruct rt-mmap-region
  (address nil)
  (length 0 :type integer)
  (prot +rt-prot-read+ :type integer)
  (flags +rt-map-private+ :type integer)
  (fd nil)
  (offset 0 :type integer)
  (path nil)
  (array nil)
  (dirty-p nil)
  (buffer nil)
  (released-p nil))

(defvar *rt-mmap-registry* (make-hash-table :test #'eql))

(defvar *rt-mmap-next-address* #x100000000)

(defvar *rt-resource-limits* (make-hash-table))

(defvar *rt-mmap-backend* nil)

(defun rt-register-mmap-backend (&key page-size anonymous-map-flag map unmap protect read-byte write-byte copy-native-to-buffer copy-buffer-to-native open-file file-size close-file sync advice reset align-next-address) (setf *rt-mmap-backend* (list :page-size page-size :anonymous-map-flag anonymous-map-flag :map map :unmap unmap :protect protect :read-byte read-byte :write-byte write-byte :copy-native-to-buffer copy-native-to-buffer :copy-buffer-to-native copy-buffer-to-native :open-file open-file :file-size file-size :close-file close-file :sync sync :advice advice :reset reset :align-next-address align-next-address) +rt-page-size+ (funcall page-size) +rt-map-anonymous+ (funcall anonymous-map-flag)) t)

(defun %rt-mmap-backend-call (operation &rest arguments) (let ((callback (getf *rt-mmap-backend* operation))) (unless callback (error "Mmap backend operation is unavailable: ~S" operation)) (apply callback arguments)))

(defun rt-page-align (size)
  (* +rt-page-size+ (ceiling size +rt-page-size+)))

(defun rt-valid-mmap-size-p (size)
  (and (integerp size) (plusp size)))

(defun rt-set-resource-limit (name value)
  (setf (gethash name *rt-resource-limits*) value))

(defun rt-resource-limit (name)
  (gethash name *rt-resource-limits*))

(defun %rt-mmap-region-for (region-or-address)
    (let ((address (if (typep region-or-address (quote rt-mmap-region))
                       (rt-mmap-region-address region-or-address)
                       region-or-address)))
      (values (gethash address *rt-mmap-registry*) address)))

  (defun %rt-normalize-map-flags (flags)
    (if (zerop (logand flags (logior +rt-map-shared+ +rt-map-private+)))
        (logior flags +rt-map-private+)
        flags))

  (defun %rt-copy-native-to-buffer (region start end)
  (%rt-mmap-backend-call :copy-native-to-buffer
                         (rt-mmap-region-address region)
                         (rt-mmap-region-buffer region)
                         start end))

  (defun %rt-copy-buffer-to-native (region start end)
  (%rt-mmap-backend-call :copy-buffer-to-native
                         (rt-mmap-region-address region)
                         (rt-mmap-region-buffer region)
                         start end))

(defun rt-mmap (addr length prot flags fd offset)
  "Create an OS-backed mmap region."
  (unless (rt-valid-mmap-size-p length)
    (error "Invalid mmap length: ~a" length))
  (when (logtest flags +rt-map-fixed+)
    (error "MAP_FIXED mappings are forbidden to protect the host Lisp heap."))
  (let* ((aligned (rt-page-align length))
         (native-flags (%rt-normalize-map-flags flags))
         (address (%rt-mmap-backend-call :map addr aligned prot native-flags fd offset))
         (region (make-rt-mmap-region
                  :address address :length aligned :prot prot :flags native-flags
                  :fd fd :offset offset
                  :buffer (make-array aligned :element-type '(unsigned-byte 8)
                                             :initial-element 0))))
    (setf (gethash address *rt-mmap-registry*) region)
    (when (not (zerop (logand prot +rt-prot-read+)))
      (%rt-copy-native-to-buffer region 0 length))
    region))

(defun rt-mmap-raw (addr length prot flags fd offset)
  (rt-mmap addr length prot flags fd offset))

(defun rt-munmap (region-or-address &optional length)
  (multiple-value-bind (region address)
      (%rt-mmap-region-for region-or-address)
    (unless region
      (error "No mmap region at address: ~a" address))
    (let ((mapped-length (rt-mmap-region-length region)))
      (when (and length (> length mapped-length))
        (error "munmap length ~a exceeds mapped length ~a" length mapped-length))
      (%rt-mmap-backend-call :unmap address mapped-length)
      (setf (rt-mmap-region-released-p region) t)
      (remhash address *rt-mmap-registry*)
      t)))

(defun rt-munmap-raw (addr length) (rt-munmap addr length))

(defun rt-mprotect (region-or-address length prot)
  (multiple-value-bind (region address)
      (%rt-mmap-region-for region-or-address)
    (unless region
      (error "No mmap region at address: ~a" address))
    (when (> length (rt-mmap-region-length region))
      (error "mprotect length ~a exceeds mapped length ~a"
             length (rt-mmap-region-length region)))
    (%rt-mmap-backend-call :protect address length prot)
    (setf (rt-mmap-region-prot region) prot)
    t))

(defun rt-mmap-buffer (region)
  (check-type region rt-mmap-region)
  (when (rt-mmap-region-released-p region)
    (error "mmap region released"))
  (rt-mmap-region-buffer region))

(defun rt-mmap-ref (region index)
  (let ((buffer (rt-mmap-buffer region)))
    (unless (not (zerop (logand (rt-mmap-region-prot region) +rt-prot-read+)))
      (error "mmap region is not readable"))
    (aref buffer index)
    (let ((value (%rt-mmap-backend-call :read-byte
                                        (rt-mmap-region-address region) index)))
      (setf (aref buffer index) value)
      value)))

(defun rt-mmap-set (region index value)
  (unless (not (zerop (logand (rt-mmap-region-prot region) +rt-prot-write+)))
    (error "mmap region is not writable"))
  (let ((buffer (rt-mmap-buffer region)))
    (setf (aref buffer index) value
          (rt-mmap-region-dirty-p region) t)
    (%rt-mmap-backend-call :write-byte
                           (rt-mmap-region-address region) index value)
    value))

(defun %rt-mmap-prot (protection)
  (ecase protection
    (:read +rt-prot-read+)
    (:read-write (logior +rt-prot-read+ +rt-prot-write+))
    (:exec (logior +rt-prot-read+ +rt-prot-exec+))))

(defun %rt-mmap-flags (flags)
  (ecase flags
    (:private +rt-map-private+)
    (:shared +rt-map-shared+)))

(defun %rt-mmap-writable-p (region)
  (not (zerop (logand (rt-mmap-region-prot region) +rt-prot-write+))))

(defun %rt-mmap-shared-p (region)
  (not (zerop (logand (rt-mmap-region-flags region) +rt-map-shared+))))

(defun mmap-file (path &key (protection :read) (flags :private) length (offset 0))
  "Map PATH with the operating systems mmap implementation."
  (let* ((name (namestring (pathname path)))
         (writable-p (eq protection :read-write))
         (fd (%rt-mmap-backend-call :open-file name writable-p))
         (file-size (%rt-mmap-backend-call :file-size fd))
         (size (or length (- file-size offset))))
    (unwind-protect
         (progn
           (unless (plusp size)
             (error "Cannot mmap an empty file: ~a" name))
           (when (> (+ offset size) file-size)
             (error "mmap range exceeds file size: ~a" name))
           (let ((region (rt-mmap nil size
                                  (%rt-mmap-prot protection)
                                  (%rt-mmap-flags flags)
                                  fd offset)))
             (setf (rt-mmap-region-path region) name
                   (rt-mmap-region-array region)
                   (make-array size :element-type '(unsigned-byte 8)
                                    :displaced-to (rt-mmap-region-buffer region)))
             region))
      (%rt-mmap-backend-call :close-file fd))))

(defun mmap-array (region)
  "Return REGION's displaced byte array for direct byte access."
  (when (rt-mmap-region-released-p region)
    (error "mmap region released"))
  (or (rt-mmap-region-array region)
      (setf (rt-mmap-region-array region)
            (make-array (rt-mmap-region-length region)
                        :element-type '(unsigned-byte 8)
                        :displaced-to (rt-mmap-region-buffer region)))))

(defun mmap-sync (region &key start end)
  "Copy the compatibility array into a shared native mapping and flush it."
  (when (rt-mmap-region-released-p region)
    (error "mmap region released"))
  (let* ((begin (or start 0))
         (finish (or end (rt-mmap-region-length region)))
         (mapped-length (rt-mmap-region-length region)))
    (unless (<= 0 begin finish mapped-length)
      (error "Invalid mmap sync range: ~a..~a" begin finish))
    (when (and (%rt-mmap-shared-p region) (%rt-mmap-writable-p region))
      (%rt-copy-buffer-to-native region begin finish)
      (%rt-mmap-backend-call :sync
                             (rt-mmap-region-address region) mapped-length))
    (setf (rt-mmap-region-dirty-p region) nil)
    t))

(defun mmap-close (region)
  "Close REGION, flushing shared writable mappings."
  (unless (rt-mmap-region-released-p region)
    (mmap-sync region)
    (rt-munmap region (rt-mmap-region-length region)))
  t)

(defmacro with-mmap ((var path &rest options) &body body)
  "Evaluate BODY with VAR bound to an mmap-file region and auto-cleaned up."
  `(let ((,var (mmap-file ,path ,@options)))
     (unwind-protect (progn ,@body)
       (mmap-close ,var))))

(defun mmap-advice (region advice &key start end)
  "Apply native madvise ADVICE to REGION."
  (check-type region rt-mmap-region)
  (when (rt-mmap-region-released-p region)
    (error "mmap region released"))
  (let* ((begin (or start 0))
         (finish (or end (rt-mmap-region-length region)))
         (length (- finish begin))
         (native-advice (ecase advice
                          (:normal 0)
                          (:random 1)
                          (:sequential 2)
                          (:will-need 3)
                          (:dont-need 4))))
    (unless (<= 0 begin finish (rt-mmap-region-length region))
      (error "Invalid mmap advice range: ~a..~a" begin finish))
    (%rt-mmap-backend-call :advice
                           (+ (rt-mmap-region-address region) begin)
                           length native-advice)
    t))

(defun rt-allocate-code-memory (size)
  (rt-mmap nil size (logior +rt-prot-read+ +rt-prot-write+ +rt-prot-exec+)
           +rt-map-anonymous+ nil 0))

(defun rt-release-code-memory (region size)
  (rt-munmap region size))

(defun rt-allocate-anonymous-memory (size &key (prot (logior +rt-prot-read+ +rt-prot-write+)))
  (rt-mmap nil size prot +rt-map-anonymous+ nil 0))

(defun rt-mmap-align-next-address (alignment)
  (setf *rt-mmap-next-address*
        (%rt-mmap-backend-call :align-next-address
                               *rt-mmap-next-address* alignment)))

(defun rt-mmap-init ()
  (let ((regions (loop for region being the hash-values of *rt-mmap-registry*
                       collect region)))
    (dolist (region regions)
      (unless (rt-mmap-region-released-p region)
        (rt-munmap region))))
  (clrhash *rt-mmap-registry*)
  (clrhash *rt-resource-limits*)
  (%rt-mmap-backend-call :reset)
  (setf *rt-mmap-next-address* #x100000000)
  t)
