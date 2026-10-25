(defpackage #:cl-cc/runtime/compression
            (:use #:cl)
            (:export #:gzip-compress
                     #:gzip-decompress
                     #:zlib-compress
                     #:zlib-decompress))
