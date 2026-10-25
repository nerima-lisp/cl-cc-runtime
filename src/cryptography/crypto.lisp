(in-package :cl-cc/runtime/cryptography)

(defun rt-sha256 (octets)
  "Compute SHA-256 for OCTETS and return its 32-byte digest."
  (digest :sha256 octets))

(defun rt-sha512 (octets)
  "Compute SHA-512 for OCTETS and return its 64-byte digest."
  (digest :sha512 octets))

(defun rt-sha256-string (string)
  "Hash STRING by mapping each character code to one byte and return lowercase hex."
  (let ((octets (map '(vector (unsigned-byte 8)) #'char-code string)))
    (octets-to-hex (rt-sha256 octets))))

(defun rt-hmac-sha256 (key msg)
  "Compute HMAC-SHA256 of MSG under KEY."
  (hmac :sha256 key msg))
