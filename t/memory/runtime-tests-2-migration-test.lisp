(in-package :cl-cc/runtime/memory/test)

;;; ─── Runtime Region Operations ─────────────────────────────────────────────
(it-sequential "rt-region-lifetime-guards-references"
               (let (escaped-ref)
                 (cl-cc/runtime/memory:rt-with-region (region)
                                               (expect
                                                (cl-cc/runtime/memory:rt-region-active-p
                                                 region)
                                                :to-be-truthy)
                                               (let ((ref
                                                      (cl-cc/runtime/memory:rt-region-alloc
                                                       region
                                                       42)))
                                                 (setf escaped-ref ref)
                                                 (expect
                                                  (cl-cc/runtime/memory:rt-region-ref-valid-p
                                                   ref)
                                                  :to-be-truthy)
                                                 (expect
                                                  (= 42
                                                     (cl-cc/runtime/memory:rt-region-deref
                                                      ref))
                                                  :to-be-truthy)))
                 (expect (cl-cc/runtime/memory:rt-region-ref-valid-p escaped-ref)
                         :to-be-falsy)
                 (signals error (cl-cc/runtime/memory:rt-region-deref escaped-ref))))

(it-sequential "rt-region-bump-pointer-accounting"
               (let ((r (cl-cc/runtime/memory:rt-make-region)))
                 (expect (= 0 (cl-cc/runtime/memory:rt-region-used r)) :to-be-truthy)
                 (let ((cap (cl-cc/runtime/memory:rt-region-capacity r)))
                   (expect (> cap 0) :to-be-truthy)
                   (cl-cc/runtime/memory:rt-region-alloc r :a)
                   (cl-cc/runtime/memory:rt-region-alloc r :b)
                   (expect (= 2 (cl-cc/runtime/memory:rt-region-used r)) :to-be-truthy)
                   (cl-cc/runtime/memory:rt-close-region r)
                   (expect (= 0 (cl-cc/runtime/memory:rt-region-used r)) :to-be-truthy))))
