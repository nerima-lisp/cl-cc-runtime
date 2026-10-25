;;;; Tests for the cl-deflate-kit compression adapters.
(in-package :cl-cc/runtime/compression/test)

(defun %bytes (&rest xs)
  (make-array (length xs) :element-type '(unsigned-byte 8) :initial-contents xs))

(defun %ascii (string)
  (map '(vector (unsigned-byte 8)) #'char-code string))

(describe "compression adapters"
          (it "zlib compression round-trips and reduces repetitive input"
              (let* ((input
                      (make-array 1024
                                  :element-type
                                  '(unsigned-byte 8)
                                  :initial-element
                                  65))
                     (compressed (zlib-compress input)))
                (expect (< (length compressed) (length input)) :to-be-truthy)
                (expect (zlib-decompress compressed) :to-equalp input)))
          (it "gzip compression round-trips and reduces repetitive input"
              (let* ((input
                      (make-array 1024
                                  :element-type
                                  '(unsigned-byte 8)
                                  :initial-element
                                  65))
                     (compressed (gzip-compress input)))
                (expect (< (length compressed) (length input)) :to-be-truthy)
                (expect (gzip-decompress compressed) :to-equalp input)))
          (it
           "signals the kit container error for invalid zlib and gzip headers"
           (signals deflate-kit:invalid-container-error
                    (zlib-decompress (%bytes 0 0)))
           (signals deflate-kit:invalid-container-error
                    (gzip-decompress (%bytes 0 0 0 0 0 0 0 0 0 0))))
          (it "validates the zlib Adler-32 and gzip CRC-32 checksums"
              (let* ((compressed (zlib-compress (%ascii "checksum")))
                     (corrupt (copy-seq compressed))
                     (last-byte (1- (length corrupt))))
                (setf (aref corrupt last-byte)
                      (logxor 1 (aref corrupt last-byte)))
                (let ((checksum-error-p nil))
                  (handler-case
                      (zlib-decompress corrupt)
                    (deflate-kit:checksum-error ()
                      (setf checksum-error-p t)))
                  (expect checksum-error-p :to-be-truthy)))
              (let* ((compressed (gzip-compress (%ascii "checksum")))
                     (corrupt (copy-seq compressed))
                     (crc-byte (- (length corrupt) 8)))
                (setf (aref corrupt crc-byte)
                      (logxor 1 (aref corrupt crc-byte)))
                (let ((checksum-error-p nil))
                  (handler-case
                      (gzip-decompress corrupt)
                    (deflate-kit:checksum-error ()
                      (setf checksum-error-p t)))
                  (expect checksum-error-p :to-be-truthy))))
          (it "forwards output limits to both kit decompressors"
              (let* ((input
                      (make-array 1024
                                  :element-type
                                  '(unsigned-byte 8)
                                  :initial-element
                                  65))
                     (zlib (zlib-compress input))
                     (gzip (gzip-compress input)))
                (signals deflate-kit:inflate-size-limit-exceeded
                         (zlib-decompress zlib :max-output 8))
                (signals deflate-kit:inflate-size-limit-exceeded
                         (gzip-decompress gzip :max-output 8)))))
