;;;; Memory-Mapped I/O (FR-349, FR-351)
(in-package :cl-cc/runtime/memory/infra)

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

  (defun %rt-mmap-sap (address)
    (sb-sys:int-sap address))

  (defun %rt-native-call-error (operation)
    (error "~A failed (errno ~D)" operation (sb-alien:get-errno)))

(defun %rt-mmap-backend-map (address length protection flags fd offset)
  (sb-sys:sap-int
   (sb-posix:mmap (if address (%rt-mmap-sap address) (sb-sys:int-sap 0))
                  length protection flags (or fd -1) offset)))

(defun %rt-mmap-backend-unmap (address length)
  (sb-posix:munmap (%rt-mmap-sap address) length))

(defun %rt-mmap-backend-protect (address length protection)
  (unless (zerop (%rt-native-mprotect address length protection))
    (%rt-native-call-error "mprotect"))
  t)

(defun %rt-mmap-backend-copy-native-to-buffer (address buffer start end)
  (let ((sap (%rt-mmap-sap address)))
    (loop for index from start below end
          do (setf (aref buffer index) (sb-sys:sap-ref-8 sap index)))))

(defun %rt-mmap-backend-copy-buffer-to-native (address buffer start end)
  (let ((sap (%rt-mmap-sap address)))
    (loop for index from start below end
          do (setf (sb-sys:sap-ref-8 sap index) (aref buffer index)))))

(defun %rt-mmap-backend-read-byte (address index)
  (sb-sys:sap-ref-8 (%rt-mmap-sap address) index))

(defun %rt-mmap-backend-write-byte (address index value)
  (setf (sb-sys:sap-ref-8 (%rt-mmap-sap address) index) value))

(defun %rt-mmap-backend-open-file (name writable-p)
  (sb-posix:open name (if writable-p sb-posix:o-rdwr sb-posix:o-rdonly)))

(defun %rt-mmap-backend-file-size (fd)
  (sb-posix:stat-size (sb-posix:fstat fd)))

(defun %rt-mmap-backend-close-file (fd)
  (sb-posix:close fd))

(defun %rt-mmap-backend-sync (address length)
  (sb-posix:msync (%rt-mmap-sap address) length sb-posix:ms-sync))

(defun %rt-mmap-backend-advice (address length advice)
  (unless (zerop (%rt-native-madvise address length advice))
    (%rt-native-call-error "madvise"))
  t)

(defun %rt-mmap-backend-reset ()
  (values))

(defun %rt-mmap-backend-align-next-address (address alignment)
  (* alignment (ceiling address alignment)))

(eval-when (:load-toplevel :execute)
  (rt-register-mmap-backend
   :page-size #'%rt-native-page-size
   :anonymous-map-flag (lambda () sb-posix:map-anon)
   :map #'%rt-mmap-backend-map
   :unmap #'%rt-mmap-backend-unmap
   :protect #'%rt-mmap-backend-protect
   :read-byte #'%rt-mmap-backend-read-byte
   :write-byte #'%rt-mmap-backend-write-byte
   :copy-native-to-buffer #'%rt-mmap-backend-copy-native-to-buffer
   :copy-buffer-to-native #'%rt-mmap-backend-copy-buffer-to-native
   :open-file #'%rt-mmap-backend-open-file
   :file-size #'%rt-mmap-backend-file-size
   :close-file #'%rt-mmap-backend-close-file
   :sync #'%rt-mmap-backend-sync
   :advice #'%rt-mmap-backend-advice
   :reset #'%rt-mmap-backend-reset
   :align-next-address #'%rt-mmap-backend-align-next-address))
