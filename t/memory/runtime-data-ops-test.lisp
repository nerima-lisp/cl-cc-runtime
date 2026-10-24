(in-package :cl-cc/runtime/memory/test)

(it-sequential
  "Region allocation advances bump index and close resets usage."
  (let ((r (cl-cc/runtime::rt-make-region)))
    (expect (cl-cc/runtime::rt-region-used r) :to-equal 0)
    (let ((cap (cl-cc/runtime::rt-region-capacity r)))
      (expect (> cap 0) :to-be-truthy)
      (cl-cc/runtime::rt-region-alloc r :a)
      (cl-cc/runtime::rt-region-alloc r :b)
      (expect (cl-cc/runtime::rt-region-used r) :to-equal 2)
      (cl-cc/runtime::rt-close-region r)
      (expect (cl-cc/runtime::rt-region-used r) :to-equal 0))))

(it-sequential
  "rt-with-region/alloc/deref enforce region lifetime at runtime."
  (let (escaped-ref)
    (cl-cc/runtime::rt-with-region
      (region)
      (expect (cl-cc/runtime::rt-region-active-p region) :to-be-truthy)
      (let ((ref (cl-cc/runtime::rt-region-alloc region 42)))
        (setf escaped-ref ref)
        (expect (cl-cc/runtime::rt-region-ref-valid-p ref) :to-be-truthy)
        (expect (cl-cc/runtime::rt-region-deref ref) :to-equal 42)))
    (expect (cl-cc/runtime::rt-region-ref-valid-p escaped-ref) :to-be-falsy)
    (signals error (cl-cc/runtime::rt-region-deref escaped-ref))))
