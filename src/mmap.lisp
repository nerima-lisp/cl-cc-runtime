;;;; Memory-Mapped I/O (FR-349, FR-351)
(in-package :cl-cc/runtime)

(progn
  (eval-when (:compile-toplevel :load-toplevel :execute)
    (require :sb-posix))
  (sb-alien:define-alien-routine ("getpagesize" %rt-native-page-size) sb-alien:int)
  (sb-alien:define-alien-routine ("mprotect" %rt-native-mprotect) sb-alien:int
    (address sb-alien:unsigned-long)
    (length sb-alien:unsigned-long)
    (protection sb-alien:int))
  (sb-alien:define-alien-routine ("madvise" %rt-native-madvise) sb-alien:int
    (address sb-alien:unsigned-long)
    (length sb-alien:unsigned-long)
    (advice sb-alien:int))
  (defparameter +rt-page-size+ (%rt-native-page-size)))
(defconstant +rt-prot-none+ 0)
(defconstant +rt-prot-read+ 1)
(defconstant +rt-prot-write+ 2)
(defconstant +rt-prot-exec+ 4)
(defconstant +rt-map-shared+ 1)
(defconstant +rt-map-private+ 2)
(defconstant +rt-map-fixed+ 16)
(defconstant +rt-map-anonymous+ sb-posix:map-anon)

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

(defun rt-page-align (size)
  (* +rt-page-size+ (ceiling size +rt-page-size+)))

(defun rt-valid-mmap-size-p (size)
  (and (integerp size) (plusp size)))

(defun rt-set-resource-limit (name value)
  (setf (gethash name *rt-resource-limits*) value))

(defun rt-resource-limit (name)
  (gethash name *rt-resource-limits*))

(progn
  (defun %rt-mmap-region-for (region-or-address)
    (let ((address (if (typep region-or-address (quote rt-mmap-region))
                       (rt-mmap-region-address region-or-address)
                       region-or-address)))
      (values (gethash address *rt-mmap-registry*) address)))

  (defun %rt-mmap-sap (address)
    (sb-sys:int-sap address))

  (defun %rt-native-call-error (operation)
    (error "~A failed (errno ~D)" operation (sb-alien:get-errno)))

  (defun %rt-normalize-map-flags (flags)
    (if (zerop (logand flags (logior +rt-map-shared+ +rt-map-private+)))
        (logior flags +rt-map-private+)
        flags))

  (defun %rt-copy-native-to-buffer (region start end)
    (let ((sap (%rt-mmap-sap (rt-mmap-region-address region)))
          (buffer (rt-mmap-region-buffer region)))
      (loop for index from start below end
            do (setf (aref buffer index) (sb-sys:sap-ref-8 sap index)))))

  (defun %rt-copy-buffer-to-native (region start end)
    (let ((sap (%rt-mmap-sap (rt-mmap-region-address region)))
          (buffer (rt-mmap-region-buffer region)))
      (loop for index from start below end
            do (setf (sb-sys:sap-ref-8 sap index) (aref buffer index))))))

(defun rt-mmap (addr length prot flags fd offset)
  "Create an OS-backed mmap region."
  (unless (rt-valid-mmap-size-p length)
    (error "Invalid mmap length: ~a" length))
  (let* ((aligned (rt-page-align length))
         (native-flags (%rt-normalize-map-flags flags))
         (sap (sb-posix:mmap (if addr (%rt-mmap-sap addr) (sb-sys:int-sap 0))
                             aligned prot native-flags (or fd -1) offset))
         (address (sb-sys:sap-int sap))
         (region (make-rt-mmap-region
                  :address address :length aligned :prot prot :flags native-flags
                  :fd fd :offset offset
                  :buffer (make-array aligned :element-type (quote (unsigned-byte 8))
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
      (sb-posix:munmap (%rt-mmap-sap address) mapped-length)
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
    (unless (zerop (%rt-native-mprotect address length prot))
      (%rt-native-call-error "mprotect"))
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
    (let ((value (sb-sys:sap-ref-8 (%rt-mmap-sap (rt-mmap-region-address region))
                                   index)))
      (setf (aref buffer index) value)
      value)))

(defun rt-mmap-set (region index value)
  (unless (not (zerop (logand (rt-mmap-region-prot region) +rt-prot-write+)))
    (error "mmap region is not writable"))
  (let ((buffer (rt-mmap-buffer region)))
    (setf (aref buffer index) value
          (sb-sys:sap-ref-8 (%rt-mmap-sap (rt-mmap-region-address region)) index) value
          (rt-mmap-region-dirty-p region) t)
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
         (open-flags (if writable-p sb-posix:o-rdwr sb-posix:o-rdonly))
         (fd (sb-posix:open name open-flags))
         (file-size (sb-posix:stat-size (sb-posix:fstat fd)))
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
                   (make-array size :element-type (quote (unsigned-byte 8))
                                    :displaced-to (rt-mmap-region-buffer region)))
             region))
      (sb-posix:close fd))))

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
      (sb-posix:msync (%rt-mmap-sap (rt-mmap-region-address region))
                      mapped-length sb-posix:ms-sync))
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
    (unless (zerop (%rt-native-madvise
                    (+ (rt-mmap-region-address region) begin)
                    length native-advice))
      (%rt-native-call-error "madvise"))
    t))

(defun rt-allocate-code-memory (size)
  (rt-mmap nil size (logior +rt-prot-read+ +rt-prot-write+ +rt-prot-exec+)
           +rt-map-anonymous+ nil 0))

(defun rt-release-code-memory (region size)
  (rt-munmap region size))

(defun rt-allocate-anonymous-memory (size &key (prot (logior +rt-prot-read+ +rt-prot-write+)))
  (rt-mmap nil size prot +rt-map-anonymous+ nil 0))

(defun rt-mmap-init ()
  (let ((regions (loop for region being the hash-values of *rt-mmap-registry*
                       collect region)))
    (dolist (region regions)
      (unless (rt-mmap-region-released-p region)
        (rt-munmap region))))
  (clrhash *rt-mmap-registry*)
  (clrhash *rt-resource-limits*)
  (setf *rt-mmap-next-address* #x100000000)
  t)
