(defpackage #:cl-cc/runtime/compression
  (:use #:cl)
  (:intern
   #:adler32
   #:crc32
  )
  (:export
   #:gzip-compress
   #:gzip-decompress
   #:zlib-compress
   #:zlib-decompress))



