;;;; tests/compress-tests.lisp — adler32 / crc32 checksums + zlib/gzip framing (src/compress.lisp).
(in-package :cl-cc-runtime/test)

(defun %bytes (&rest xs)
  (make-array (length xs) :element-type '(unsigned-byte 8) :initial-contents xs))

(defun %ascii (string)
  (map '(vector (unsigned-byte 8)) #'char-code string))

(describe "adler32 (compress.lisp)"
  (it "of the empty vector is 1"
    (expect (cl-cc/runtime::adler32 (%bytes)) :to-be 1))

  ;; Canonical reference value: adler32(\"abc\") = #x024D0127.
  (it "matches the reference checksum for \"abc\""
    (expect (cl-cc/runtime::adler32 (%ascii "abc")) :to-be #x024D0127))

  (it-property "always fits in 32 bits"
      ((bytes (gen-list (gen-integer :min 0 :max 255) :max-length 64)))
    (let ((v (make-array (length bytes) :element-type '(unsigned-byte 8)
                                        :initial-contents bytes)))
      (expect (<= 0 (cl-cc/runtime::adler32 v) #xFFFFFFFF) :to-be-truthy))))

(describe "crc32 (compress.lisp)"
  (it "of the empty vector is 0"
    (expect (cl-cc/runtime::crc32 (%bytes)) :to-be 0))

  ;; Canonical reference value: crc32(\"abc\") = #x352441C2.
  (it "matches the reference checksum for \"abc\""
    (expect (cl-cc/runtime::crc32 (%ascii "abc")) :to-be #x352441C2))

  (it "matches the reference checksum for the standard \"123456789\" vector"
    (expect (cl-cc/runtime::crc32 (%ascii "123456789")) :to-be #xCBF43926))

  (it-property "always fits in 32 bits"
      ((bytes (gen-list (gen-integer :min 0 :max 255) :max-length 64)))
    (let ((v (make-array (length bytes) :element-type '(unsigned-byte 8)
                                        :initial-contents bytes)))
      (expect (<= 0 (cl-cc/runtime::crc32 v) #xFFFFFFFF) :to-be-truthy))))

(describe "zlib framing (compress.lisp)"
  (it "prepends the 0x78 0x01 zlib header and appends a 4-byte adler trailer"
    (let* ((o (%bytes 1 2 3 4 5))
           (c (cl-cc/runtime::zlib-compress o)))
      (expect (aref c 0) :to-be #x78)
      (expect (aref c 1) :to-be #x01)
      ;; header(2) + stored-deflate(5 + n) + adler(4)
      (expect (length c) :to-be (+ (length o) 11))))

  (it "the stored-deflate trailer carries the adler32 of the payload"
    (let* ((o (%ascii "abc"))
           (c (cl-cc/runtime::zlib-compress o))
           (ad (cl-cc/runtime::adler32 o))
           (n (length c)))
      (expect (aref c (- n 4)) :to-be (ldb (byte 8 24) ad))
      (expect (aref c (- n 1)) :to-be (ldb (byte 8 0) ad))))

  (it "zlib-decompress strips the outer framing, preserving the payload after the block header"
    (let* ((o (%bytes 9 8 7 6))
           (c (cl-cc/runtime::zlib-compress o))
           (d (cl-cc/runtime::zlib-decompress c)))
      ;; d = 5-byte stored-deflate block header ++ original payload.
      (expect (subseq d 5) :to-equalp o)))

  (it "zlib-decompress returns short inputs unchanged"
    (let ((tiny (%bytes 1 2 3)))
      (expect (cl-cc/runtime::zlib-decompress tiny) :to-equalp tiny))))

(describe "gzip framing (compress.lisp)"
  (it "prepends the gzip magic 1f 8b 08 and appends an 8-byte crc/size trailer"
    (let* ((o (%bytes 1 2 3 4 5))
           (c (cl-cc/runtime::gzip-compress o)))
      (expect (aref c 0) :to-be #x1f)
      (expect (aref c 1) :to-be #x8b)
      (expect (aref c 2) :to-be #x08)
      ;; header(10) + stored-deflate(5 + n) + crc(4) + isize(4)
      (expect (length c) :to-be (+ (length o) 23))))

  (it "the gzip trailer carries the little-endian crc32 and input size"
    (let* ((o (%ascii "abc"))
           (c (cl-cc/runtime::gzip-compress o))
           (cr (cl-cc/runtime::crc32 o))
           (n (length c)))
      (expect (aref c (- n 8)) :to-be (ldb (byte 8 0) cr))
      (expect (aref c (- n 5)) :to-be (ldb (byte 8 24) cr))
      (expect (aref c (- n 4)) :to-be (ldb (byte 8 0) (length o)))))

  (it "gzip-decompress strips the outer framing, preserving the payload after the block header"
    (let* ((o (%bytes 5 4 3 2 1 0))
           (c (cl-cc/runtime::gzip-compress o))
           (d (cl-cc/runtime::gzip-decompress c)))
      (expect (subseq d 5) :to-equalp o)))

  (it "gzip-decompress returns short inputs unchanged"
    (let ((tiny (%bytes 1 2 3 4)))
      (expect (cl-cc/runtime::gzip-decompress tiny) :to-equalp tiny))))
