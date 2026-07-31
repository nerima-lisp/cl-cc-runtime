;;;; t/crypto-test.lisp
;;;;
;;;; Known-answer tests for src/crypto.lisp against published FIPS 180-4
;;;; (SHA-256/SHA-512), RFC 4231 (HMAC-SHA256) and RFC 4648 (Base64) vectors.
;;;; These vectors are the proof of correctness: a failure here means the
;;;; implementation is wrong, not the expectation.
(in-package :cl-cc-runtime/test)

;;; ─── Helpers ────────────────────────────────────────────────────────────────
(defun %str->octets (string)
  (map '(vector (unsigned-byte 8)) #'char-code string))

(defun %digest->hex (digest)
  (with-output-to-string (out)
    (loop for b across digest
          do (format out "~(~2,'0x~)" b))))

;;; ─── SHA-256 (FIPS 180-4) ───────────────────────────────────────────────────
(it-sequential-each
  (("empty" "" "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    ("abc" "abc" "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    ("two-block"
      "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
      "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"))
  "SHA-256 matches FIPS 180-4 known-answer vectors (~A)"
  (label input expected)
  (declare (ignore label))
  (expect (%digest->hex (rt-sha256 (%str->octets input))) :to-equal expected))

(it-sequential
  "rt-sha256-string returns lowercase hex matching the raw digest."
  (expect
    (rt-sha256-string "")
    :to-equal
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  (expect
    (rt-sha256-string "abc")
    :to-equal
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))

;;; ─── SHA-512 (FIPS 180-4) ───────────────────────────────────────────────────
(it-sequential-each
  (("empty"
      ""
      "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e")
    ("abc"
      "abc"
      "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")
    ("multi-block"
      "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"
      "8e959b75dae313da8cf4f72814fc143f8f7779c6eb9f7fa17299aeadb6889018501d289e4900f7e4331b99dec4b5433ac7d329eeb6dd26545e96e55b874be909"))
  "SHA-512 matches FIPS 180-4 known-answer vectors (~A)"
  (label input expected)
  (declare (ignore label))
  (expect (%digest->hex (rt-sha512 (%str->octets input))) :to-equal expected))

;;; ─── HMAC-SHA256 (RFC 4231) ─────────────────────────────────────────────────
(it-sequential "HMAC-SHA256 matches RFC 4231 Test Case 1 and Test Case 2."
  ;; Test Case 1: key = 0x0b x20, data = "Hi There"
  (expect (%digest->hex
                 (rt-hmac-sha256
                  (make-array 20 :element-type '(unsigned-byte 8) :initial-element #x0b)
                  (%str->octets "Hi There"))) :to-equal "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7")
  ;; Test Case 2: key = "Jefe", data = "what do ya want for nothing?"
  (expect (%digest->hex
                 (rt-hmac-sha256
                  (%str->octets "Jefe")
                  (%str->octets "what do ya want for nothing?"))) :to-equal "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"))

;;; ─── Base64 (RFC 4648) ──────────────────────────────────────────────────────
(it-sequential-each (("f" "f" "Zg==")
                      ("fo" "fo" "Zm8=")
                      ("foo" "foo" "Zm9v")
                      ("foob" "foob" "Zm9vYg==")
                      ("fooba" "fooba" "Zm9vYmE=")
                      ("foobar" "foobar" "Zm9vYmFy")
                      ("Man" "Man" "TWFu"))
    "Base64 standard-alphabet encoding matches RFC 4648 vectors (~A)"
    (label input expected)
  (declare (ignore label))
  (expect (rt-base64-encode (%str->octets input)) :to-equal expected))

(it-sequential
  "URL-safe alphabet uses - and _ where the standard alphabet uses + and /."
  (let ((octets
        (make-array
          3
          :element-type
          '(unsigned-byte 8)
          :initial-contents
          '(#xff #xff #xff))))
    (expect (rt-base64-encode octets) :to-equal "////")
    (expect (rt-base64-encode octets :url-safe t) :to-equal "____"))
  (let ((octets
        (make-array 1 :element-type '(unsigned-byte 8) :initial-contents '(#xfb))))
    (expect (rt-base64-encode octets) :to-equal "+w==")
    (expect (rt-base64-encode octets :url-safe t) :to-equal "-w==")))

(it-sequential "base64 encode then decode reproduces the original octets." (dolist (bytes '((0 1 2 3 4 5)
                   (255 254 253)
                   (72 101 108 108 111)
                   (0)
                   (0 0)))
    (let* ((octets (make-array (length bytes) :element-type '(unsigned-byte 8)
                                              :initial-contents bytes))
           (decoded (rt-base64-decode (rt-base64-encode octets))))
      (expect (coerce decoded 'list) :to-equal (coerce octets 'list))))
  ;; URL-safe round-trip.
  (let* ((octets (make-array 3 :element-type '(unsigned-byte 8)
                               :initial-contents '(#xfb #xef #xbe)))
         (decoded (rt-base64-decode (rt-base64-encode octets :url-safe t) :url-safe t)))
    (expect (coerce decoded 'list) :to-equal (coerce octets 'list))))

(it-property "base64 encode then decode reproduces arbitrary octet vectors of arbitrary length"
    ((bytes (gen-vector (gen-integer :min 0 :max 255) :min-length 0 :max-length 64)))
  (let* ((octets (coerce bytes '(vector (unsigned-byte 8))))
         (decoded (rt-base64-decode (rt-base64-encode octets))))
    (expect (coerce decoded 'list) :to-equal (coerce octets 'list))))

(defparameter +base64-fuzz-alphabet+
  (concatenate 'string
               "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="
               (string #\Space) (string #\Tab)
               ;; Codepoints past ASCII: the lookup table rt-base64-decode
               ;; builds only covers 0-127, so these exercise the bounds
               ;; check guarding that table access.
               (string (code-char 233))    ; é, U+00E9
               (string (code-char 12354))  ; あ, U+3042
               (string (code-char 128512)) ; 😀, U+1F600
               )
  "Alphabet for the RT-BASE64-DECODE fuzz test below: valid Base64 characters
plus padding, whitespace, and three codepoints chosen to be past the ASCII
range at increasing widths (Latin-1 supplement, BMP, and a codepoint needing
a UTF-16 surrogate pair / 4-byte UTF-8 encoding).")

(it-fuzz "rt-base64-decode never signals on arbitrary input, including whitespace, padding, and non-ASCII characters outside the alphabet"
    ((s (gen-string :min-length 0 :max-length 40 :alphabet +base64-fuzz-alphabet+)))
    (:trials 50 :timeout-per-trial 1)
  (rt-base64-decode s))
