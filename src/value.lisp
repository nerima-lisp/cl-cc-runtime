;;;; packages/runtime/src/value.lisp - NaN-Boxing Value Representation
;;;
;;; Simulates 64-bit NaN-boxing on top of SBCL using (unsigned-byte 64) integers.
;;; All VM instructions input and output boxed values (type VAL = (unsigned-byte 64)).
;;;
;;; The tag/mask layout constants this file's predicates and encoders read are
;;; in value-tags.lisp (loaded first). Pinned unboxed-array buffers, which need
;;; the pointer codec in value-codec.lisp, are in value-pinned-array.lisp
;;; (loaded after it).
;;;
;;; Bit layout:
;;;
;;;   Fixnum:    bits[63:13] sign-extended integer, bits[12:0] = 0 (tag = 0000)
;;;              Encoding: (ash integer 13)  — 51-bit signed integers
;;;
;;;   Double:    Any bit pattern that is NOT a quiet NaN with our tag flag set.
;;;              Decoded by reinterpreting bits as IEEE 754 double via LDB.
;;;
;;;   Pointer:   Quiet NaN base (bits[62:51] = #x7FF, bit[50] = 1) + 3-bit tag in bits[50:48]
;;;              + 48-bit address in bits[47:0].  When pointer compression is
;;;              enabled, bit[47] marks a compressed payload and bits[31:0]
;;;              carry an offset from *HEAP-BASE-ADDRESS*.
;;;              Base mask: #x7FF8000000000000
;;;              Tag in bits [50:48]:
;;;                001 = Object   (general heap object)
;;;                010 = Cons     (cons cell)
;;;                011 = Symbol
;;;                100 = Function (closure)
;;;                101 = String
;;;
;;;   Character: Quiet NaN base #x7FFE000000000000 + 21-bit codepoint in bits[20:0]
;;;
;;;   Nil:       #x7FFF000000000000
;;;   T:         #x7FFF000000000001
;;;   Unbound:   #x7FFF000000000002
;;;
;;;   Immediate symbols:
;;;              #x7FFF000000000100 + small index in bits[7:0]
;;;              NIL and T keep their dedicated singleton encodings above.
;;;
;;;   SSO string: bits[63:59]=#b01110, bits[58:3] store up to 7 character
;;;               bytes little-endian by index, bits[2:0] store byte length.

(in-package :cl-cc/runtime)

(declaim (optimize (speed 3) (safety 1)))

;;; ------------------------------------------------------------
;;; Type predicates  (inline for performance)
;;; ------------------------------------------------------------

(declaim (ftype (function ((unsigned-byte 64)) boolean)
                val-fixnum-p val-double-p val-pointer-p
                val-compressed-pointer-p
                val-nil-p val-t-p val-char-p val-unbound-p
                val-object-p val-cons-p val-symbol-p val-function-p val-string-p
                val-sso-string-p val-immediate-symbol-p))

(declaim (inline val-fixnum-p val-double-p val-pointer-p
                 val-compressed-pointer-p
                 val-nil-p val-t-p val-char-p val-unbound-p
                 val-object-p val-cons-p val-symbol-p val-function-p val-string-p
                 val-sso-string-p val-immediate-symbol-p encode-immediate-symbol-index
                 immediate-symbol-index decode-immediate-symbol))

(defun val-sso-string-p (v)
  "True if V is an inline small-string immediate value."
  (declare (type (unsigned-byte 64) v))
  (= (logand v +sso-string-mask+) +sso-string-base+))

(defun val-fixnum-p (v)
  "True if V is a boxed fixnum: low 13 bits all zero AND not in NaN-tagged space.

   The NaN-tagged space occupies [+nan-tag-base+, #x8000000000000000) — a narrow
   positive range with exponent bits all-ones.  Negative fixnums have bit 63 = 1
   (value >= #x8000000000000000) and therefore fall ABOVE the NaN-tagged range;
   they must not be rejected by the +nan-tag-base+ guard."
  (declare (type (unsigned-byte 64) v))
  (and (zerop (logand v +fixnum-mask+))
       (not (val-sso-string-p v))
       ;; Exclude only the NaN-tagged range.  It is entirely positive (bit 63 = 0),
       ;; so values with bit 63 = 1 (negative fixnums) are never in NaN space.
       (not (and (zerop (ldb (byte 1 63) v))    ; positive (bit 63 = 0)
                 (>= v +nan-tag-base+)))))

(defun val-double-p (v)
  "True if V encodes an IEEE 754 double (not in our NaN-tagged space)."
  (declare (type (unsigned-byte 64) v))
  ;; A value is a double if it is NOT in our special NaN space.
  ;; Our NaN space: bits[62:51] = #x7FF and bit[50..49] != 00
  ;; (fixnums have low bits clear so they escape this).
  ;; Practical check: v >= +nan-tag-base+ and NOT fixnum and NOT char/ptr/special.
  (and (not (val-fixnum-p v))
       (not (val-sso-string-p v))
       (< v +nan-tag-base+)))

(defun val-pointer-p (v)
  "True if V is any pointer-tagged value (object/cons/symbol/function/string).
   Pointer upper-16-bits range: #x7FF9 (object/tag=001) to #x7FFD (string/tag=101)."
  ;; Extract upper 16 bits and check they fall in the pointer sub-tag range.
  (and (typep v '(unsigned-byte 64))
       (let ((h (ash v -48)))
         (declare (type (unsigned-byte 16) h))
         (and (>= h #x7FF9) (<= h #x7FFD)))))

(defun val-compressed-pointer-p (v)
  "True if V is a pointer-tagged value carrying a 32-bit heap-relative offset."
  (declare (type (unsigned-byte 64) v))
  (and (val-pointer-p v)
       (not (zerop (logand v +compressed-pointer-flag+)))))

(declaim (inline %val-ptr-tag))
(defun %val-ptr-tag (v)
  "Extract the 3-bit sub-tag from a pointer value."
  (declare (type (unsigned-byte 64) v))
  (logand v +tag-mask+))

(defun val-object-p (v)
  (declare (type (unsigned-byte 64) v))
  (= (logand v +ptr-mask+) (logior +ptr-base+ +tag-object+)))

(defun val-cons-p (v)
  (declare (type (unsigned-byte 64) v))
  (= (logand v +ptr-mask+) (logior +ptr-base+ +tag-cons+)))

(defun val-symbol-p (v)
  (declare (type (unsigned-byte 64) v))
  (or (= (logand v +ptr-mask+) (logior +ptr-base+ +tag-symbol+))
      (val-immediate-symbol-p v)))

(defun val-immediate-symbol-p (v)
  "True if V is one of the frequent-symbol immediate values."
  (declare (type (unsigned-byte 64) v))
  (= (logand v +immediate-symbol-mask+) +immediate-symbol-base+))

(defun encode-immediate-symbol-index (index)
  "Encode immediate symbol table INDEX as a NaN-boxed immediate value."
  (declare (type (unsigned-byte 8) index))
  (logand (logior +immediate-symbol-base+ index) +max-u64+))

(defun immediate-symbol-index (v)
  "Return the immediate symbol table index carried by V."
  (declare (type (unsigned-byte 64) v))
  (logand v +immediate-symbol-index-mask+))

(defun decode-immediate-symbol (v)
  "Decode an immediate symbol value to its host CL symbol."
  (declare (type (unsigned-byte 64) v))
  (unless (val-immediate-symbol-p v)
    (error "decode-immediate-symbol: not an immediate symbol #x~16,'0X" v))
  (svref *immediate-symbol-table* (immediate-symbol-index v)))

(defun immediate-symbol-value (symbol)
  "Return SYMBOL's immediate encoding, or NIL when SYMBOL is heap-backed."
  (let ((index (and (symbolp symbol) (gethash symbol *immediate-symbol-indexes*))))
    (and index (encode-immediate-symbol-index index))))

(defun val-function-p (v)
  (declare (type (unsigned-byte 64) v))
  (= (logand v +ptr-mask+) (logior +ptr-base+ +tag-function+)))

(defun val-string-p (v)
  (declare (type (unsigned-byte 64) v))
  (or (val-sso-string-p v)
      (= (logand v +ptr-mask+) (logior +ptr-base+ +tag-string+))))

(defun %sso-string-byte-p (char)
  "True if CHAR can be stored as one inline byte."
  (declare (type character char))
  (<= (char-code char) #xFF))

(defun encode-sso-string (string)
  "Encode STRING as an inline small-string immediate.

STRING must contain at most seven one-byte characters.  Longer strings or
characters with codes above #xFF must use the heap string representation."
  (check-type string string)
  (let ((length (length string)))
    (unless (<= length +sso-string-max-length+)
      (error "encode-sso-string: string length ~D exceeds SSO limit ~D"
             length +sso-string-max-length+))
    (let ((payload 0))
      (loop for i from 0 below length
            for char = (char string i)
            for code = (char-code char)
            do (unless (%sso-string-byte-p char)
                 (error "encode-sso-string: non-byte character ~S at index ~D"
                        char i))
               (setf payload (logand (logior payload (ash code (+ 3 (* 8 i))))
                                     +max-u64+)))
      (logand (logior +sso-string-base+
                      length
                      payload)
              +max-u64+))))

(defun decode-sso-string (value)
  "Decode an inline small-string immediate VALUE into a host CL string."
  (declare (type (unsigned-byte 64) value))
  (unless (val-sso-string-p value)
    (error "decode-sso-string: not an SSO string #x~16,'0X" value))
  (let* ((length (logand value +sso-string-length-mask+))
         (string (make-string length)))
    (loop for i from 0 below length
          do (setf (char string i)
                   (code-char (ldb (byte 8 (+ 3 (* 8 i))) value))))
    string))

(defun val-char-p (v)
  "True if V is a boxed character."
  (declare (type (unsigned-byte 64) v))
  (= (logand v #xFFFF000000000000) +tag-char+))

(defun val-nil-p (v)
  (declare (type (unsigned-byte 64) v))
  (= v +val-nil+))

(defun val-t-p (v)
  (declare (type (unsigned-byte 64) v))
  (= v +val-t+))

(defun val-unbound-p (v)
  (declare (type (unsigned-byte 64) v))
  (= v +val-unbound+))
