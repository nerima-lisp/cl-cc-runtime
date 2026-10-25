(in-package :cl-cc/runtime/compression)

(defun zlib-compress (octets &key (level 6))
  (deflate-kit:zlib-compress octets :level level))

(defun zlib-decompress (octets &key max-output)
  (deflate-kit:zlib-decompress octets :max-output max-output))

(defun gzip-compress (octets)
  (deflate-kit:gzip-compress octets))

(defun gzip-decompress (octets &key max-output)
  (nth-value 0 (deflate-kit:gzip-decompress octets :max-output max-output)))
