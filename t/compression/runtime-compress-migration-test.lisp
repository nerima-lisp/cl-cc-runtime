;;;; t/compression/runtime-compress-migration-test.lisp
(in-package :cl-cc/runtime/compression/test)

(defun %string-octets (string)
  (map '(vector (unsigned-byte 8)) #'char-code string))

(defun %octet-string (octets)
  (map 'string #'code-char octets))

(it-sequential "fr-740-zlib-stored-block-roundtrip"
               (let* ((plain "zlib payload")
                      (bytes (%string-octets plain))
                      (compressed
                       (cl-cc/runtime/compression:zlib-compress bytes))
                      (decompressed
                       (cl-cc/runtime/compression:zlib-decompress compressed)))
                 (expect (%octet-string decompressed) :to-equal plain)))

(it-sequential "fr-740-gzip-stored-block-roundtrip"
               (let* ((plain "gzip payload")
                      (bytes (%string-octets plain))
                      (compressed
                       (cl-cc/runtime/compression:gzip-compress bytes))
                      (decompressed
                       (cl-cc/runtime/compression:gzip-decompress compressed)))
                 (expect (%octet-string decompressed) :to-equal plain)))
