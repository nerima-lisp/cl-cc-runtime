(in-package :cl-cc/runtime)

;;;; Cryptographic primitives — self-contained, dependency-free reference
;;;; implementations of SHA-256, SHA-512 (FIPS 180-4), HMAC-SHA256 (RFC 2104)
;;;; and Base64 (RFC 4648, standard and URL-safe alphabets). Operate on
;;;; (vector (unsigned-byte 8)) octet vectors unless noted otherwise.

;;; ── Shared bit helpers ──────────────────────────────────────────────
;;; SHA rotations are RIGHT ROTATIONS (ROTR), not plain shifts: the bits
;;; shifted off the low end wrap back into the high end. A plain (ash x -n)
;;; drops those bits and yields a different, incorrect digest.

(declaim (inline %sha-ch %sha-maj
                 %rotr32 %sha256-ls0 %sha256-ls1 %sha256-us0 %sha256-us1
                 %rotr64 %sha512-ls0 %sha512-ls1 %sha512-us0 %sha512-us1))

(defun %sha-ch (x y z)
  "SHA choose function: for each bit, pick Y where X is 1, else Z."
  (logxor (logand x y) (logand (lognot x) z)))

(defun %sha-maj (x y z)
  "SHA majority function: for each bit, the value held by at least two of X, Y, Z."
  (logxor (logand x y) (logand x z) (logand y z)))

;;; ── SHA-256 constants and round functions (32-bit words) ────────────

(defparameter +sha256-h+
  #(#x6a09e667 #xbb67ae85 #x3c6ef372 #xa54ff53a
    #x510e527f #x9b05688c #x1f83d9ab #x5be0cd19)
  "SHA-256 initial hash value (FIPS 180-4 §5.3.3).")

(defparameter +sha256-k+
  #(#x428a2f98 #x71374491 #xb5c0fbcf #xe9b5dba5 #x3956c25b #x59f111f1 #x923f82a4 #xab1c5ed5
    #xd807aa98 #x12835b01 #x243185be #x550c7dc3 #x72be5d74 #x80deb1fe #x9bdc06a7 #xc19bf174
    #xe49b69c1 #xefbe4786 #x0fc19dc6 #x240ca1cc #x2de92c6f #x4a7484aa #x5cb0a9dc #x76f988da
    #x983e5152 #xa831c66d #xb00327c8 #xbf597fc7 #xc6e00bf3 #xd5a79147 #x06ca6351 #x14292967
    #x27b70a85 #x2e1b2138 #x4d2c6dfc #x53380d13 #x650a7354 #x766a0abb #x81c2c92e #x92722c85
    #xa2bfe8a1 #xa81a664b #xc24b8b70 #xc76c51a3 #xd192e819 #xd6990624 #xf40e3585 #x106aa070
    #x19a4c116 #x1e376c08 #x2748774c #x34b0bcb5 #x391c0cb3 #x4ed8aa4a #x5b9cca4f #x682e6ff3
    #x748f82ee #x78a5636f #x84c87814 #x8cc70208 #x90befffa #xa4506ceb #xbef9a3f7 #xc67178f2)
  "SHA-256 round constants (FIPS 180-4 §4.2.2).")

(defun %rotr32 (x n)
  "Right-rotate the 32-bit word X by N bits."
  (logand (logior (ash x (- n)) (ash x (- 32 n))) #xFFFFFFFF))

(defun %sha256-ls0 (x)
  "SHA-256 lowercase sigma 0: ROTR7 xor ROTR18 xor SHR3."
  (logxor (%rotr32 x 7) (%rotr32 x 18) (ash x -3)))

(defun %sha256-ls1 (x)
  "SHA-256 lowercase sigma 1: ROTR17 xor ROTR19 xor SHR10."
  (logxor (%rotr32 x 17) (%rotr32 x 19) (ash x -10)))

(defun %sha256-us0 (x)
  "SHA-256 uppercase sigma 0: ROTR2 xor ROTR13 xor ROTR22."
  (logxor (%rotr32 x 2) (%rotr32 x 13) (%rotr32 x 22)))

(defun %sha256-us1 (x)
  "SHA-256 uppercase sigma 1: ROTR6 xor ROTR11 xor ROTR25."
  (logxor (%rotr32 x 6) (%rotr32 x 11) (%rotr32 x 25)))

(defun rt-sha256 (octets)
  "Compute the SHA-256 digest of OCTETS, a (vector (unsigned-byte 8)).
Returns a fresh 32-byte (vector (unsigned-byte 8)) big-endian digest."
  (let* ((ml (length octets))
         (bl (* ml 8))
         (pad (mod (- 56 (mod (1+ ml) 64)) 64))
         (tl (+ ml 1 pad 8))
         (h (copy-seq +sha256-h+))
         (w (make-array 64 :element-type '(unsigned-byte 32) :initial-element 0))
         (buf (make-array tl :element-type '(unsigned-byte 8) :initial-element 0)))
    (replace buf octets)
    (setf (aref buf ml) #x80)
    (dotimes (i 8)
      (setf (aref buf (- tl 1 i)) (ldb (byte 8 (* 8 i)) bl)))
    (dotimes (ci (/ tl 64))
      (dotimes (i 16)
        (let ((base (+ (* ci 64) (* i 4))))
          (setf (aref w i)
                (logior (ash (aref buf (+ base 0)) 24)
                        (ash (aref buf (+ base 1)) 16)
                        (ash (aref buf (+ base 2)) 8)
                        (aref buf (+ base 3))))))
      (loop for i from 16 to 63 do
        (setf (aref w i)
              (logand (+ (aref w (- i 16))
                         (%sha256-ls0 (aref w (- i 15)))
                         (aref w (- i 7))
                         (%sha256-ls1 (aref w (- i 2))))
                      #xFFFFFFFF)))
      (let ((a (aref h 0)) (b (aref h 1)) (c (aref h 2)) (d (aref h 3))
            (e (aref h 4)) (f (aref h 5)) (g (aref h 6)) (hv (aref h 7)))
        (dotimes (i 64)
          (let ((t1 (logand (+ hv
                               (%sha256-us1 e)
                               (%sha-ch e f g)
                               (aref +sha256-k+ i)
                               (aref w i))
                            #xFFFFFFFF))
                (t2 (logand (+ (%sha256-us0 a) (%sha-maj a b c))
                            #xFFFFFFFF)))
            (setf hv g
                  g f
                  f e
                  e (logand (+ d t1) #xFFFFFFFF)
                  d c
                  c b
                  b a
                  a (logand (+ t1 t2) #xFFFFFFFF))))
        (setf (aref h 0) (logand (+ (aref h 0) a) #xFFFFFFFF)
              (aref h 1) (logand (+ (aref h 1) b) #xFFFFFFFF)
              (aref h 2) (logand (+ (aref h 2) c) #xFFFFFFFF)
              (aref h 3) (logand (+ (aref h 3) d) #xFFFFFFFF)
              (aref h 4) (logand (+ (aref h 4) e) #xFFFFFFFF)
              (aref h 5) (logand (+ (aref h 5) f) #xFFFFFFFF)
              (aref h 6) (logand (+ (aref h 6) g) #xFFFFFFFF)
              (aref h 7) (logand (+ (aref h 7) hv) #xFFFFFFFF))))
    (let ((r (make-array 32 :element-type '(unsigned-byte 8))))
      (dotimes (i 8)
        (let ((wd (aref h i)))
          (setf (aref r (+ (* i 4) 0)) (ldb (byte 8 24) wd)
                (aref r (+ (* i 4) 1)) (ldb (byte 8 16) wd)
                (aref r (+ (* i 4) 2)) (ldb (byte 8 8) wd)
                (aref r (+ (* i 4) 3)) (ldb (byte 8 0) wd))))
      r)))

;;; ── SHA-512 constants and round functions (64-bit words) ────────────

(defconstant +sha512-mask+ #xFFFFFFFFFFFFFFFF
  "64-bit truncation mask for SHA-512 modular word arithmetic.")

(defparameter +sha512-h+
  #(#x6a09e667f3bcc908 #xbb67ae8584caa73b #x3c6ef372fe94f82b #xa54ff53a5f1d36f1
    #x510e527fade682d1 #x9b05688c2b3e6c1f #x1f83d9abfb41bd6b #x5be0cd19137e2179)
  "SHA-512 initial hash value (FIPS 180-4 §5.3.5).")

(defparameter +sha512-k+
  #(#x428a2f98d728ae22 #x7137449123ef65cd #xb5c0fbcfec4d3b2f #xe9b5dba58189dbbc
    #x3956c25bf348b538 #x59f111f1b605d019 #x923f82a4af194f9b #xab1c5ed5da6d8118
    #xd807aa98a3030242 #x12835b0145706fbe #x243185be4ee4b28c #x550c7dc3d5ffb4e2
    #x72be5d74f27b896f #x80deb1fe3b1696b1 #x9bdc06a725c71235 #xc19bf174cf692694
    #xe49b69c19ef14ad2 #xefbe4786384f25e3 #x0fc19dc68b8cd5b5 #x240ca1cc77ac9c65
    #x2de92c6f592b0275 #x4a7484aa6ea6e483 #x5cb0a9dcbd41fbd4 #x76f988da831153b5
    #x983e5152ee66dfab #xa831c66d2db43210 #xb00327c898fb213f #xbf597fc7beef0ee4
    #xc6e00bf33da88fc2 #xd5a79147930aa725 #x06ca6351e003826f #x142929670a0e6e70
    #x27b70a8546d22ffc #x2e1b21385c26c926 #x4d2c6dfc5ac42aed #x53380d139d95b3df
    #x650a73548baf63de #x766a0abb3c77b2a8 #x81c2c92e47edaee6 #x92722c851482353b
    #xa2bfe8a14cf10364 #xa81a664bbc423001 #xc24b8b70d0f89791 #xc76c51a30654be30
    #xd192e819d6ef5218 #xd69906245565a910 #xf40e35855771202a #x106aa07032bbd1b8
    #x19a4c116b8d2d0c8 #x1e376c085141ab53 #x2748774cdf8eeb99 #x34b0bcb5e19b48a8
    #x391c0cb3c5c95a63 #x4ed8aa4ae3418acb #x5b9cca4f7763e373 #x682e6ff3d6b2b8a3
    #x748f82ee5defb2fc #x78a5636f43172f60 #x84c87814a1f0ab72 #x8cc702081a6439ec
    #x90befffa23631e28 #xa4506cebde82bde9 #xbef9a3f7b2c67915 #xc67178f2e372532b
    #xca273eceea26619c #xd186b8c721c0c207 #xeada7dd6cde0eb1e #xf57d4f7fee6ed178
    #x06f067aa72176fba #x0a637dc5a2c898a6 #x113f9804bef90dae #x1b710b35131c471b
    #x28db77f523047d84 #x32caab7b40c72493 #x3c9ebe0a15c9bebc #x431d67c49c100d4c
    #x4cc5d4becb3e42b6 #x597f299cfc657e2a #x5fcb6fab3ad6faec #x6c44198c4a475817)
  "SHA-512 round constants: 80 words, first 64 bits of the fractional parts
of the cube roots of the first 80 primes (FIPS 180-4 §4.2.3).")

(defun %rotr64 (x n)
  "Right-rotate the 64-bit word X by N bits."
  (logand (logior (ash x (- n)) (ash x (- 64 n))) +sha512-mask+))

(defun %sha512-ls0 (x)
  "SHA-512 lowercase sigma 0: ROTR1 xor ROTR8 xor SHR7."
  (logxor (%rotr64 x 1) (%rotr64 x 8) (ash x -7)))

(defun %sha512-ls1 (x)
  "SHA-512 lowercase sigma 1: ROTR19 xor ROTR61 xor SHR6."
  (logxor (%rotr64 x 19) (%rotr64 x 61) (ash x -6)))

(defun %sha512-us0 (x)
  "SHA-512 uppercase sigma 0: ROTR28 xor ROTR34 xor ROTR39."
  (logxor (%rotr64 x 28) (%rotr64 x 34) (%rotr64 x 39)))

(defun %sha512-us1 (x)
  "SHA-512 uppercase sigma 1: ROTR14 xor ROTR18 xor ROTR41."
  (logxor (%rotr64 x 14) (%rotr64 x 18) (%rotr64 x 41)))

(defun rt-sha512 (octets)
  "Compute the SHA-512 digest of OCTETS, a (vector (unsigned-byte 8)).
Returns a fresh 64-byte (vector (unsigned-byte 8)) big-endian digest.
Uses 64-bit words, 80 rounds, and a 128-bit big-endian message-length
field, per FIPS 180-4."
  (let* ((ml (length octets))
         (bl (* ml 8))
         (pad (mod (- 112 (mod (1+ ml) 128)) 128))
         (tl (+ ml 1 pad 16))
         (h (copy-seq +sha512-h+))
         (w (make-array 80 :element-type '(unsigned-byte 64) :initial-element 0))
         (buf (make-array tl :element-type '(unsigned-byte 8) :initial-element 0)))
    (replace buf octets)
    (setf (aref buf ml) #x80)
    (dotimes (i 16)
      (setf (aref buf (- tl 1 i)) (ldb (byte 8 (* 8 i)) bl)))
    (dotimes (ci (/ tl 128))
      (dotimes (i 16)
        (let ((base (+ (* ci 128) (* i 8)))
              (word 0))
          (dotimes (j 8)
            (setf word (logior (ash word 8) (aref buf (+ base j)))))
          (setf (aref w i) word)))
      (loop for i from 16 to 79 do
        (setf (aref w i)
              (logand (+ (aref w (- i 16))
                         (%sha512-ls0 (aref w (- i 15)))
                         (aref w (- i 7))
                         (%sha512-ls1 (aref w (- i 2))))
                      +sha512-mask+)))
      (let ((a (aref h 0)) (b (aref h 1)) (c (aref h 2)) (d (aref h 3))
            (e (aref h 4)) (f (aref h 5)) (g (aref h 6)) (hv (aref h 7)))
        (dotimes (i 80)
          (let ((t1 (logand (+ hv
                               (%sha512-us1 e)
                               (%sha-ch e f g)
                               (aref +sha512-k+ i)
                               (aref w i))
                            +sha512-mask+))
                (t2 (logand (+ (%sha512-us0 a) (%sha-maj a b c))
                            +sha512-mask+)))
            (setf hv g
                  g f
                  f e
                  e (logand (+ d t1) +sha512-mask+)
                  d c
                  c b
                  b a
                  a (logand (+ t1 t2) +sha512-mask+))))
        (setf (aref h 0) (logand (+ (aref h 0) a) +sha512-mask+)
              (aref h 1) (logand (+ (aref h 1) b) +sha512-mask+)
              (aref h 2) (logand (+ (aref h 2) c) +sha512-mask+)
              (aref h 3) (logand (+ (aref h 3) d) +sha512-mask+)
              (aref h 4) (logand (+ (aref h 4) e) +sha512-mask+)
              (aref h 5) (logand (+ (aref h 5) f) +sha512-mask+)
              (aref h 6) (logand (+ (aref h 6) g) +sha512-mask+)
              (aref h 7) (logand (+ (aref h 7) hv) +sha512-mask+))))
    (let ((r (make-array 64 :element-type '(unsigned-byte 8))))
      (dotimes (i 8)
        (let ((wd (aref h i)))
          (dotimes (j 8)
            (setf (aref r (+ (* i 8) j)) (ldb (byte 8 (* 8 (- 7 j))) wd)))))
      r)))

;;; ── Convenience and MAC constructions ───────────────────────────────

(defun rt-sha256-string (string)
  "Compute the SHA-256 of STRING (each character taken as its char-code byte)
and return the digest as a 64-character lowercase hexadecimal string."
  (let* ((octets (map '(vector (unsigned-byte 8)) #'char-code string))
         (h (rt-sha256 octets)))
    (with-output-to-string (out)
      (dotimes (i 32)
        (format out "~(~2,'0x~)" (aref h i))))))

(defun rt-hmac-sha256 (key msg)
  "Compute HMAC-SHA256 (RFC 2104) of MSG under KEY. KEY and MSG are
(vector (unsigned-byte 8)). Returns a fresh 32-byte (vector (unsigned-byte 8))."
  (let* ((bs 64)
         (k (if (> (length key) bs)
                (let ((kk (make-array bs :element-type '(unsigned-byte 8) :initial-element 0)))
                  (replace kk (rt-sha256 key))
                  kk)
                (let ((kk (make-array bs :element-type '(unsigned-byte 8) :initial-element 0)))
                  (replace kk key)
                  kk)))
         (okp (make-array bs :element-type '(unsigned-byte 8)))
         (ikp (make-array bs :element-type '(unsigned-byte 8))))
    (dotimes (i bs)
      (setf (aref okp i) (logxor (aref k i) #x5c)
            (aref ikp i) (logxor (aref k i) #x36)))
    (rt-sha256 (concatenate '(vector (unsigned-byte 8))
                            okp
                            (rt-sha256 (concatenate '(vector (unsigned-byte 8)) ikp msg))))))

;;; ── Base64 (RFC 4648) ───────────────────────────────────────────────

(defparameter +b64-alpha+
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  "Standard Base64 alphabet (RFC 4648 §4).")

(defparameter +b64url-alpha+
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
  "URL- and filename-safe Base64 alphabet (RFC 4648 §5).")

(defun rt-base64-encode (octets &key (url-safe nil))
  "Base64-encode OCTETS, a (vector (unsigned-byte 8)). When URL-SAFE is true,
use the URL-safe alphabet (- and _ in place of + and /). Returns a string,
padded with '=' to a multiple of 4 characters."
  (let* ((alpha (if url-safe +b64url-alpha+ +b64-alpha+))
         (n (length octets))
         (rl (* 4 (ceiling n 3)))
         (r (make-string rl :initial-element #\=)))
    (loop with ri = 0
          for i from 0 below n by 3
          do (let* ((b0 (aref octets i))
                    (b1 (if (< (+ i 1) n) (aref octets (+ i 1)) 0))
                    (b2 (if (< (+ i 2) n) (aref octets (+ i 2)) 0))
                    (triple (logior (ash b0 16) (ash b1 8) b2)))
               (setf (char r (+ ri 0)) (char alpha (ldb (byte 6 18) triple))
                     (char r (+ ri 1)) (char alpha (ldb (byte 6 12) triple)))
               (setf (char r (+ ri 2))
                     (if (< (+ i 1) n) (char alpha (ldb (byte 6 6) triple)) #\=))
               (setf (char r (+ ri 3))
                     (if (< (+ i 2) n) (char alpha (ldb (byte 6 0) triple)) #\=))
               (incf ri 4)))
    r))

(defun rt-base64-decode (string &key (url-safe nil))
  "Decode the Base64 STRING back into a (vector (unsigned-byte 8)). When
URL-SAFE is true, decode the URL-safe alphabet. Surrounding whitespace and
'=' padding are ignored."
  (let* ((s (string-trim '(#\Space #\Newline #\Return #\Tab) string))
         (alpha (if url-safe +b64url-alpha+ +b64-alpha+))
         (lk (make-array 128 :element-type '(unsigned-byte 8) :initial-element 255)))
    (dotimes (i 64)
      (setf (aref lk (char-code (char alpha i))) i))
    (let ((v 0))
      (loop for c across s unless (char= c #\=) do (incf v))
      (let ((rl (floor (* v 3) 4))
            (buf 0)
            (bits 0)
            (ri 0))
        (let ((r (make-array rl :element-type '(unsigned-byte 8))))
          (loop for c across s
                for idx = (aref lk (char-code c))
                when (/= idx 255)
                  do (setf buf (logior (ash buf 6) idx)
                           bits (+ bits 6))
                     (when (>= bits 8)
                       (setf bits (- bits 8)
                             (aref r ri) (ldb (byte 8 bits) buf))
                       (incf ri)))
          r)))))
