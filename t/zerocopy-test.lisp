(in-package :cl-cc-runtime/test)
(in-suite cl-cc-unit-suite)

;;;; Tests for src/zerocopy.lisp — buffer registry + portable sendfile/splice.
;;;;
;;;; The registry is a global hash table, so rt-zerocopy-init is called to reset
;;;; it. sendfile/splice are exercised against real temporary binary files since
;;;; they operate on octet streams. Registered-buffer struct accessors are
;;;; unexported (cl-cc/runtime:: below).

;;; ── Buffer registry ───────────────────────────────────────────────

(deftest zerocopy-register-and-lookup
  "A registered buffer is retrievable and carries its pin flag."
  (rt-zerocopy-init)
  (let ((data (vector 1 2 3)))
    (assert-true (rt-register-buffer :a data :pin t))
    (let ((reg (cl-cc/runtime::rt-registered-buffer :a)))
      (assert-eq data (cl-cc/runtime::rt-registered-buffer-buffer reg))
      (assert-true (cl-cc/runtime::rt-registered-buffer-pinned-p reg)))))

(deftest zerocopy-unregister-removes-entry
  "Unregistering drops the buffer from the registry."
  (rt-zerocopy-init)
  (rt-register-buffer :b (vector 0))
  (rt-unregister-buffer :b)
  (assert-null (cl-cc/runtime::rt-registered-buffer :b)))

(deftest zerocopy-init-clears-registry
  "Init clears all previously registered buffers."
  (rt-register-buffer :c (vector 0))
  (rt-zerocopy-init)
  (assert-null (cl-cc/runtime::rt-registered-buffer :c)))

;;; ── copy-buffer ───────────────────────────────────────────────────

(deftest zerocopy-copy-buffer-full
  "Copy transfers the whole source into the target and returns the count."
  (rt-zerocopy-init)
  (let ((src (vector 1 2 3 4))
        (dst (make-array 4 :initial-element 0)))
    (rt-register-buffer :src src)
    (rt-register-buffer :dst dst)
    (assert-= 4 (rt-copy-buffer :src :dst))
    (assert-equalp #(1 2 3 4) dst)))

(deftest zerocopy-copy-buffer-range
  "Copy honors :start and :end bounds on the source."
  (rt-zerocopy-init)
  (let ((src (vector 10 20 30 40))
        (dst (make-array 4 :initial-element 0)))
    (rt-register-buffer :src src)
    (rt-register-buffer :dst dst)
    ;; copy src[1:3] = 20,30 into dst from index 0
    (assert-= 2 (rt-copy-buffer :src :dst :start 1 :end 3))
    (assert-equalp #(20 30 0 0) dst)))

;;; ── sendfile / splice ─────────────────────────────────────────────

(defun %zc-write-bytes (path bytes)
  (with-open-file (o path :direction :output :element-type '(unsigned-byte 8)
                          :if-exists :supersede)
    (write-sequence bytes o))
  path)

(defun %zc-read-bytes (path)
  (with-open-file (in path :element-type '(unsigned-byte 8))
    (let ((buf (make-array (file-length in) :element-type '(unsigned-byte 8))))
      (read-sequence buf in)
      buf)))

(deftest zerocopy-sendfile-copies-all-bytes
  "sendfile streams every byte from IN to OUT and returns the count written."
  (let ((inp (merge-pathnames "cc-zc-in.bin" (uiop:temporary-directory)))
        (outp (merge-pathnames "cc-zc-out.bin" (uiop:temporary-directory))))
    (unwind-protect
         (progn
           (%zc-write-bytes inp #(5 6 7 8 9))
           (let ((n (with-open-file (in inp :element-type '(unsigned-byte 8))
                      (with-open-file (out outp :direction :output
                                                :element-type '(unsigned-byte 8)
                                                :if-exists :supersede)
                        (cl-cc/runtime::rt-sendfile out in)))))
             (assert-= 5 n)
             (assert-equalp #(5 6 7 8 9) (%zc-read-bytes outp))))
      (ignore-errors (delete-file inp))
      (ignore-errors (delete-file outp)))))

(deftest zerocopy-sendfile-offset-and-count
  "sendfile can seek to OFFSET and copy at most COUNT bytes."
  (let ((inp (merge-pathnames "cc-zc-in2.bin" (uiop:temporary-directory)))
        (outp (merge-pathnames "cc-zc-out2.bin" (uiop:temporary-directory))))
    (unwind-protect
         (progn
           (%zc-write-bytes inp #(0 1 2 3 4 5 6 7))
           (let ((n (with-open-file (in inp :element-type '(unsigned-byte 8))
                      (with-open-file (out outp :direction :output
                                                :element-type '(unsigned-byte 8)
                                                :if-exists :supersede)
                        (cl-cc/runtime::rt-sendfile out in 2 3)))))
             (assert-= 3 n)
             (assert-equalp #(2 3 4) (%zc-read-bytes outp))))
      (ignore-errors (delete-file inp))
      (ignore-errors (delete-file outp)))))

(deftest zerocopy-splice-delegates-to-sendfile
  "splice copies COUNT bytes from IN to OUT."
  (let ((inp (merge-pathnames "cc-zc-in3.bin" (uiop:temporary-directory)))
        (outp (merge-pathnames "cc-zc-out3.bin" (uiop:temporary-directory))))
    (unwind-protect
         (progn
           (%zc-write-bytes inp #(9 8 7 6))
           (let ((n (with-open-file (in inp :element-type '(unsigned-byte 8))
                      (with-open-file (out outp :direction :output
                                                :element-type '(unsigned-byte 8)
                                                :if-exists :supersede)
                        (rt-splice in out 2)))))
             (assert-= 2 n)
             (assert-equalp #(9 8) (%zc-read-bytes outp))))
      (ignore-errors (delete-file inp))
      (ignore-errors (delete-file outp)))))
