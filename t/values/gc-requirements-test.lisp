(in-package :cl-cc/runtime/values/test)

(defun %fr-assert-pointer-tags (expected-tags)
  (dolist (case expected-tags)
    (destructuring-bind (addr tag) case
      (expect (cl-cc/runtime::pointer-tag
                 (cl-cc/runtime::encode-pointer addr tag)) :to-equal tag))))

(it-sequential "FR-336: NaN-boxing pointer predicate rejects immediate non-pointer values." (expect (cl-cc/runtime::val-pointer-p
                 (cl-cc/runtime::encode-fixnum 42)) :to-be-falsy)
  (expect (cl-cc/runtime::val-pointer-p cl-cc/runtime:+val-t+) :to-be-falsy)
  (expect (cl-cc/runtime::val-pointer-p cl-cc/runtime:+val-nil+) :to-be-falsy))

(it-sequential "FR-336: Encoded pointers round-trip through decode-pointer." (let* ((addr #xABCD)
         (encoded (cl-cc/runtime::encode-pointer addr cl-cc/runtime:+tag-object+)))
    (expect (cl-cc/runtime::val-pointer-p encoded) :to-be-truthy)
    (expect (cl-cc/runtime::decode-pointer encoded) :to-equal addr)))

(it-sequential "FR-336: Pointer sub-tags are correctly extracted from NaN-boxed values." (%fr-assert-pointer-tags
   `((#x100 ,cl-cc/runtime:+tag-object+)
     (#x200 ,cl-cc/runtime:+tag-cons+)
     (#x300 ,cl-cc/runtime:+tag-symbol+))))

(it-sequential "FR-336: NaN-boxing cons predicate detects cons-tagged pointers only." (let ((cons-ptr (cl-cc/runtime::encode-pointer #x500 cl-cc/runtime:+tag-cons+))
        (obj-ptr (cl-cc/runtime::encode-pointer #x600 cl-cc/runtime:+tag-object+)))
    (expect (cl-cc/runtime::val-cons-p cons-ptr) :to-be-truthy)
    (expect (cl-cc/runtime::val-cons-p obj-ptr) :to-be-falsy)))

(it-sequential "FR-140: NIL, T, and common keywords/symbols are immediate values, not heap pointers." (expect (cl-cc/runtime::cl-value->val nil) :to-equal cl-cc/runtime:+val-nil+)
  (expect (cl-cc/runtime::cl-value->val t) :to-equal cl-cc/runtime:+val-t+)
  (let ((encoded (cl-cc/runtime::cl-value->val :key)))
    (expect (cl-cc/runtime::val-immediate-symbol-p encoded) :to-be-truthy)
    (expect (cl-cc/runtime::val-pointer-p encoded) :to-be-falsy)
    (expect (cl-cc/runtime::val->cl-value encoded) :to-be :key)))

(it-sequential "FR-264: Pointer compression stores heap-relative offsets and decodes to the original address." (let ((cl-cc/runtime::*compressed-pointers-enabled* t)
        (cl-cc/runtime::*heap-base-address* #x10000000))
    (let ((encoded (cl-cc/runtime::encode-pointer #x10001000 cl-cc/runtime:+tag-object+)))
      (expect (cl-cc/runtime::val-compressed-pointer-p encoded) :to-be-truthy)
      (expect (cl-cc/runtime::decode-pointer encoded) :to-equal #x10001000))))

(it-sequential "FR-265: Small byte strings are encoded as SSO immediates and round-trip without heap allocation." (let ((encoded (cl-cc/runtime::cl-value->val "abc")))
    (expect (cl-cc/runtime::val-sso-string-p encoded) :to-be-truthy)
    (expect (cl-cc/runtime::val->cl-value encoded) :to-equal "abc")))
