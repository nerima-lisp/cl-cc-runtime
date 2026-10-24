;;;; crypto-base64.lisp — Base64 (RFC 4648, standard and URL-safe alphabets),
;;;; split out of crypto.lisp
(in-package :cl-cc/runtime)

;;; ── Base64 (RFC 4648) ──

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
                ;; LK only covers the ASCII range; a codepoint past it is
                ;; never in the alphabet, so it gets the same "ignore" 255
                ;; sentinel as any other out-of-alphabet ASCII character
                ;; instead of an out-of-bounds AREF.
                for code = (char-code c)
                for idx = (if (< code 128) (aref lk code) 255)
                when (/= idx 255)
                  do (setf buf (logior (ash buf 6) idx)
                           bits (+ bits 6))
                     (when (>= bits 8)
                       (setf bits (- bits 8)
                             (aref r ri) (ldb (byte 8 bits) buf))
                       (incf ri)))
          r)))))
