;;;; tests/crypto-tests.lisp
;;;;
;;;; Known-answer tests for src/crypto.lisp against published FIPS 180-4
;;;; (SHA-256/SHA-512), RFC 4231 (HMAC-SHA256) and RFC 4648 (Base64) vectors.
;;;; These vectors are the proof of correctness: a failure here means the
;;;; implementation is wrong, not the expectation.

(in-package :cl-cc-runtime/test)

(in-suite cl-cc-unit-suite)

;;; ─── Helpers ────────────────────────────────────────────────────────────────

(defun %str->octets (string)
  (map '(vector (unsigned-byte 8)) #'char-code string))

(defun %digest->hex (digest)
  (with-output-to-string (out)
    (loop for b across digest do (format out "~(~2,'0x~)" b))))

;;; ─── SHA-256 (FIPS 180-4) ───────────────────────────────────────────────────

(deftest-each crypto-sha256-vectors
  "SHA-256 matches FIPS 180-4 known-answer vectors."
  :cases (("empty" ""
           "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
          ("abc" "abc"
           "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
          ("two-block"
           "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
           "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"))
  (input expected)
  (assert-equal expected (%digest->hex (rt-sha256 (%str->octets input)))))

(deftest crypto-sha256-string
  "rt-sha256-string returns lowercase hex matching the raw digest."
  (assert-equal "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
                (rt-sha256-string ""))
  (assert-equal "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
                (rt-sha256-string "abc")))

;;; ─── SHA-512 (FIPS 180-4) ───────────────────────────────────────────────────

(deftest-each crypto-sha512-vectors
  "SHA-512 matches FIPS 180-4 known-answer vectors."
  :cases (("empty" ""
           "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e")
          ("abc" "abc"
           "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")
          ("multi-block"
           "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"
           "8e959b75dae313da8cf4f72814fc143f8f7779c6eb9f7fa17299aeadb6889018501d289e4900f7e4331b99dec4b5433ac7d329eeb6dd26545e96e55b874be909"))
  (input expected)
  (assert-equal expected (%digest->hex (rt-sha512 (%str->octets input)))))

;;; ─── HMAC-SHA256 (RFC 4231) ─────────────────────────────────────────────────

(deftest crypto-hmac-sha256-rfc4231
  "HMAC-SHA256 matches RFC 4231 Test Case 1 and Test Case 2."
  ;; Test Case 1: key = 0x0b x20, data = "Hi There"
  (assert-equal "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
                (%digest->hex
                 (rt-hmac-sha256
                  (make-array 20 :element-type '(unsigned-byte 8) :initial-element #x0b)
                  (%str->octets "Hi There"))))
  ;; Test Case 2: key = "Jefe", data = "what do ya want for nothing?"
  (assert-equal "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
                (%digest->hex
                 (rt-hmac-sha256
                  (%str->octets "Jefe")
                  (%str->octets "what do ya want for nothing?")))))

;;; ─── Base64 (RFC 4648) ──────────────────────────────────────────────────────

(deftest-each crypto-base64-encode-known
  "Base64 standard-alphabet encoding matches RFC 4648 vectors."
  :cases (("f"      "f"      "Zg==")
          ("fo"     "fo"     "Zm8=")
          ("foo"    "foo"    "Zm9v")
          ("foob"   "foob"   "Zm9vYg==")
          ("fooba"  "fooba"  "Zm9vYmE=")
          ("foobar" "foobar" "Zm9vYmFy")
          ("Man"    "Man"    "TWFu"))
  (input expected)
  (assert-equal expected (rt-base64-encode (%str->octets input))))

(deftest crypto-base64-url-safe
  "URL-safe alphabet uses - and _ where the standard alphabet uses + and /."
  (let ((octets (make-array 3 :element-type '(unsigned-byte 8)
                              :initial-contents '(#xff #xff #xff))))
    (assert-equal "////" (rt-base64-encode octets))
    (assert-equal "____" (rt-base64-encode octets :url-safe t)))
  (let ((octets (make-array 1 :element-type '(unsigned-byte 8)
                              :initial-contents '(#xfb))))
    (assert-equal "+w==" (rt-base64-encode octets))
    (assert-equal "-w==" (rt-base64-encode octets :url-safe t))))

(deftest crypto-base64-roundtrip
  "base64 encode then decode reproduces the original octets."
  (dolist (bytes '((0 1 2 3 4 5)
                   (255 254 253)
                   (72 101 108 108 111)
                   (0)
                   (0 0)))
    (let* ((octets (make-array (length bytes) :element-type '(unsigned-byte 8)
                                              :initial-contents bytes))
           (decoded (rt-base64-decode (rt-base64-encode octets))))
      (assert-equal (coerce octets 'list) (coerce decoded 'list))))
  ;; URL-safe round-trip.
  (let* ((octets (make-array 3 :element-type '(unsigned-byte 8)
                               :initial-contents '(#xfb #xef #xbe)))
         (decoded (rt-base64-decode (rt-base64-encode octets :url-safe t) :url-safe t)))
    (assert-equal (coerce octets 'list) (coerce decoded 'list))))
