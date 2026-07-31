;;;; value-tags.lisp — NaN-boxed value tag/mask layout constants (the DATA
;;;; half of value.lisp's representation; predicates and codecs that operate
;;;; on it are the LOGIC half, in value.lisp and value-codec.lisp)
(in-package :cl-cc/runtime)

(defconstant +max-u64+ #xFFFFFFFFFFFFFFFF
  "All-ones 64-bit mask.  Used to force u64 representation from integer
   operations that SBCL may otherwise represent as bignums.")

;;; ------------------------------------------------------------
;;; Core bit-pattern constants
;;; ------------------------------------------------------------

;;; Quiet NaN base: exponent all-ones (bits[62:52]=7FF) + quiet bit (bit[51]=1).
;;; We use bit[50] as the "tagged pointer" discriminator — when set, this is a
;;; pointer value; when clear (but still NaN), it is a character or special.
(defconstant +nan-boxing-quiet-nan+  #x7FF8000000000000
  "IEEE 754 quiet NaN canonical bit pattern (positive, no payload).")

;;; Pointer values use +nan-boxing-quiet-nan+ as the base, with bits[50:48] = 000.
;;; OR-ing one of the 3-bit sub-tags (001..101) into bits[50:48] gives each kind
;;; a distinct upper-16-bit pattern:
;;;   object=001  → upper16=#x7FF9
;;;   cons=010    → upper16=#x7FFA
;;;   symbol=011  → upper16=#x7FFB
;;;   function=100→ upper16=#x7FFC
;;;   string=101  → upper16=#x7FFD
;;; Character (#x7FFE) and nil/t/unbound (#x7FFF) therefore cannot collide.
(defconstant +ptr-base+     #x7FF8000000000000
  "Base bit pattern for pointer-tagged values (= quiet NaN, bits[50:48]=000).")

(defconstant +ptr-mask+     #x7FFF000000000000
  "Mask covering the NaN prefix + all tag bits (bits[63:48]).")

(defconstant +tag-mask+     #x0007000000000000
  "Isolates the 3-bit sub-tag from a pointer value (bits[50:48]).")

(defconstant +addr-mask+    #x0000FFFFFFFFFFFF
  "Isolates the 48-bit address payload from a pointer value.")

(defconstant +compressed-pointer-flag+ #x0000800000000000
  "Payload bit marking a pointer value whose low 32 bits are heap-relative.")

(defconstant +compressed-pointer-offset-mask+ #x00000000FFFFFFFF
  "Mask selecting the 32-bit compressed pointer offset payload.")

(defconstant +compressed-heap-region-bytes+ #x100000000
  "Maximum byte size of a heap region addressable by compressed pointers.")

(defconstant +compressed-heap-region-words+ #x20000000
  "Maximum 8-byte words in the 4GB compressed pointer heap region.")

(defparameter *compressed-pointers-enabled* nil
  "When true, pointer NaN-box payloads store 32-bit offsets from *HEAP-BASE-ADDRESS*.")

(defparameter *heap-base-address* 0
  "Logical start address of the managed heap region used for pointer compression.")

;;; 3-bit pointer sub-tags (shifted to bits[50:48])
(defconstant +tag-object+   #x0001000000000000  "Heap object sub-tag.")

(defconstant +tag-cons+     #x0002000000000000  "Cons cell sub-tag.")

(defconstant +tag-symbol+   #x0003000000000000  "Symbol sub-tag.")

(defconstant +tag-function+ #x0004000000000000  "Function/closure sub-tag.")

(defconstant +tag-string+   #x0005000000000000  "String sub-tag.")

;;; Character: quiet NaN with bit[50] clear but bit[49] set.
;;; Base = #x7FFE_... gives bit[49]=1, bit[50]=0 → distinct from pointers.
(defconstant +tag-char+     #x7FFE000000000000
  "Base bit pattern for character immediate values.")

;;; Special singleton values (quiet NaN space, bits[50:49]=11).
(defconstant +val-nil+      #x7FFF000000000000  "Boxed NIL.")

(defconstant +val-t+        #x7FFF000000000001  "Boxed T.")

(defconstant +val-unbound+  #x7FFF000000000002  "Unbound-slot sentinel.")

;;; A compact immediate-symbol subspace inside the already-reserved #x7FFF
;;; singleton range.  The low byte is the symbol table index; the next byte is
;;; fixed to #x01 so these values cannot collide with NIL/T/UNBOUND.
(defconstant +immediate-symbol-base+ #x7FFF000000000100
  "Base bit pattern for frequent symbol immediate values.")

(defconstant +immediate-symbol-mask+ #xFFFFFFFFFFFFFF00
  "Mask selecting the fixed immediate-symbol prefix.")

(defconstant +immediate-symbol-index-mask+ #xFF
  "Mask selecting the 8-bit immediate-symbol table index.")

(defconstant +sso-string-base+ #x7000000000000000
  "Base marker for small-string immediate values.")

(defconstant +sso-string-mask+ #xF800000000000000
  "Mask selecting the fixed SSO marker bits in the top byte.")

(defconstant +sso-string-length-mask+ #x7
  "Mask selecting the 3-bit SSO length field.")

(defconstant +sso-string-max-length+ 7
  "Maximum number of inline bytes in an SSO string.")

(defparameter *immediate-symbol-table*
  #(:key :value :test :test-not :start :end :from-end :count :initial-value
    :element-type :initial-element :allow-other-keys :adjustable :fill-pointer
    quote lambda function declare setq setf if progn let let* block return-from
    tagbody go catch throw unwind-protect flet labels macrolet symbol-macrolet
    the values multiple-value-bind multiple-value-call eval-when locally and or
    cond case typecase ecase ccase loop do do* dolist dotimes defun defmacro
    defvar defparameter defconstant defclass defmethod defgeneric car cdr cons
    list append apply funcall)
  "Small canonical table of frequent symbols encoded without heap allocation.
NIL and T intentionally remain +VAL-NIL+ and +VAL-T+, not entries here.")

(defparameter *immediate-symbol-indexes*
  (let ((table (make-hash-table :test #'eq)))
    (loop for sym across *immediate-symbol-table*
          for i from 0
          do (setf (gethash sym table) i))
    table)
  "Host symbol -> immediate-symbol index mapping.")

;;; Fixnum: tag = 0 (bits[12:0] = 0), integer in bits[63:13].
;;; A valid boxed fixnum has its low 13 bits all zero.
(defconstant +fixnum-tag+   0)

(defconstant +fixnum-mask+  #x1FFF  "Low 13 bits; zero means fixnum.")

(defconstant +fixnum-shift+ 13      "Bits to shift integer for fixnum encoding.")

;;; Double detection: a double is any (unsigned-byte 64) that is NOT in our
;;; tagged NaN space.  Our tagged NaN space starts at #x7FF8000000000000
;;; with bit[50] or bit[49] set.  The simplest discriminant: if
;;; bits[62:49] = #x3FFE (i.e., upper 15 bits after bit63 = 0111_1111_1111_110x)
;;; then it is a pointer or special.  We detect doubles as "not NaN-tagged".
(defconstant +nan-tag-base+ #x7FF8000000000000
  "Minimum value whose upper bits indicate our NaN-tagged space.")
