;;;; t/image-test.lisp — Coverage for src/image.lisp and src/image-restore.lisp
;;;;
;;;; Registered-global capture, in-memory restore, binary save/load roundtrip,
;;;; validation, and hot-reload with preserved globals.
;;;;
;;;; (The native core path — rt-save-core / rt-load-core in image-core.lisp — is
;;;; covered by image-core-test.lisp; this file targets the binary
;;;; runtime-image path.)
(in-package :cl-cc-runtime/test)

(defvar *image-test-var* nil)

;;; Each test binds the image registries so registration never leaks globally.
(defmacro with-fresh-image-state (&body body)
  `(let ((cl-cc/runtime::*rt-image-globals* nil)
        (cl-cc/runtime::*rt-image-restore-hooks* nil)
        (cl-cc/runtime::*rt-code-version* 0))
    ,@body))

(defun %image-temp (name)
  (merge-pathnames name (uiop:temporary-directory)))

;;; ------------------------------------------------------------
;;; Registration
;;; ------------------------------------------------------------
(it-sequential
  "rt-image-init clears globals, hooks, and the code version."
  (let ((cl-cc/runtime::*rt-image-globals* '(x))
        (cl-cc/runtime::*rt-image-restore-hooks* (list #'identity))
        (cl-cc/runtime::*rt-code-version* 9))
    (cl-cc/runtime::rt-image-init)
    (expect cl-cc/runtime::*rt-image-globals* :to-be-null)
    (expect cl-cc/runtime::*rt-image-restore-hooks* :to-be-null)
    (expect cl-cc/runtime::*rt-code-version* :to-equal 0)))

(it-sequential
  "rt-image-register-global adds a symbol once, ignoring duplicates."
  (with-fresh-image-state
    (cl-cc/runtime::rt-image-register-global '*image-test-var*)
    (cl-cc/runtime::rt-image-register-global '*image-test-var*)
    (expect cl-cc/runtime::*rt-image-globals* :to-equal '(*image-test-var*))))

(it-sequential
  "rt-image-register-restore-hook records a hook function once."
  (with-fresh-image-state
    (let ((hook
          (lambda (x)
            (declare (ignore x))
            nil)))
      (cl-cc/runtime::rt-image-register-restore-hook hook)
      (cl-cc/runtime::rt-image-register-restore-hook hook)
      (expect (length cl-cc/runtime::*rt-image-restore-hooks*) :to-equal 1))))

;;; ------------------------------------------------------------
;;; In-memory capture / restore
;;; ------------------------------------------------------------
(it-sequential
  "rt-capture-image-state snapshots global values and the code version."
  (with-fresh-image-state
    (setf *image-test-var* '(:snapshot 1))
    (setf cl-cc/runtime::*rt-code-version* 5)
    (let ((image (cl-cc/runtime::rt-capture-image-state :globals '(*image-test-var*))))
      (expect (cl-cc/runtime::rt-image-p image) :to-be-truthy)
      (expect (cl-cc/runtime::rt-image-code-version image) :to-equal 5)
      (expect
        (assoc '*image-test-var* (cl-cc/runtime::rt-image-globals image))
        :to-equal
        '(*image-test-var* (:snapshot 1))))))

(it-sequential
  "rt-restore-image-state re-installs captured global values."
  (with-fresh-image-state
    (setf *image-test-var* '(:original))
    (let ((image (cl-cc/runtime::rt-capture-image-state :globals '(*image-test-var*))))
      (setf *image-test-var* :mutated)
      (cl-cc/runtime::rt-restore-image-state image)
      (expect *image-test-var* :to-equal '(:original)))))

;;; ------------------------------------------------------------
;;; Validation
;;; ------------------------------------------------------------
(it-sequential
  "rt-validate-image accepts an image with correct magic and version."
  (expect
    (cl-cc/runtime::rt-validate-image (cl-cc/runtime::make-rt-image))
    :to-be-truthy))

(it-sequential
  "rt-validate-image rejects a header with the wrong magic number."
  (signals error (cl-cc/runtime::rt-validate-image
          (cl-cc/runtime::make-rt-image
            :header
            (cl-cc/runtime::make-rt-image-header :magic 0))))
  (signals error (cl-cc/runtime::rt-validate-image 42)))

;;; ------------------------------------------------------------
;;; Binary save / load
;;; ------------------------------------------------------------
(it-sequential
  "rt-save-image then rt-load-image restores a registered global's value."
  (with-fresh-image-state
    (let ((path (%image-temp "clcc-runtime-image.img")))
      (setf *image-test-var* '(1 2 3 "hi"))
      (cl-cc/runtime::rt-save-image path :globals '(*image-test-var*))
      (setf *image-test-var* :mutated)
      (cl-cc/runtime::rt-load-image path)
      (expect *image-test-var* :to-equal '(1 2 3 "hi"))
      (ignore-errors (delete-file path)))))

(it-sequential "rt-load-image signals when the CRC-protected payload is truncated." (with-fresh-image-state
    (let ((path (%image-temp "clcc-runtime-image-bad.img")))
      (setf *image-test-var* '(7 8 9))
      (cl-cc/runtime::rt-save-image path :globals '(*image-test-var*))
      ;; Corrupt one payload byte in the middle of the file (before the CRC).
      (let ((bytes (with-open-file (s path :element-type '(unsigned-byte 8))
                     (let ((v (make-array (file-length s)
                                          :element-type '(unsigned-byte 8))))
                       (read-sequence v s)
                       v))))
        (setf (aref bytes (floor (length bytes) 2))
              (logxor (aref bytes (floor (length bytes) 2)) #xff))
        (with-open-file (s path :direction :output :if-exists :supersede
                                :element-type '(unsigned-byte 8))
          (write-sequence bytes s)))
      (signals error (cl-cc/runtime::rt-load-image path))
      (ignore-errors (delete-file path)))))

;;; ------------------------------------------------------------
;;; Hot reload
;;; ------------------------------------------------------------
(it-sequential
  "rt-hot-reload bumps the code version and restores preserved globals."
  (with-fresh-image-state
    (setf *image-test-var* :before)
    (let ((version
          (cl-cc/runtime::rt-hot-reload
            (lambda ()
              (setf *image-test-var* :during)
              :done)
            :preserve-globals
            '(*image-test-var*))))
      (expect version :to-equal 1)
      (expect *image-test-var* :to-be :before))))
