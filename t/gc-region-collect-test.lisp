;;;; t/gc-region-collect-test.lisp -- mixed region selection and fallback.
(in-package :cl-cc-runtime/test)

(describe "region mixed collection"
  (it "creates an old-space region array and resolves old addresses"
    (let ((heap (cl-cc/runtime::make-rt-heap :young-size 32 :old-size 16)))
      (expect (length (cl-cc/runtime::rt-heap-regions heap)) :to-be 1)
      (expect (cl-cc/runtime::rt-heap-region-for-address
               heap (cl-cc/runtime::rt-heap-old-base heap)) :to-be-truthy)))
  (it "selects a region and records evacuation failure for the fallback path"
    (let ((heap (cl-cc/runtime::make-rt-heap :young-size 32 :old-size 16)))
      (let ((addr (cl-cc/runtime::rt-gc-alloc heap :old 2)))
        (cl-cc/runtime::rt-heap-set-header
         heap addr (cl-cc/runtime::make-rt-header 2 1 :gc-bits 0))
        (let ((region (aref (cl-cc/runtime::rt-heap-regions heap) 0)))
          (cl-cc/runtime::rt-heap-set-header
           heap addr (cl-cc/runtime::header-set-mark
                      (cl-cc/runtime::rt-heap-object-header heap addr)))
          (let ((result (cl-cc/runtime::rt-gc-region-mixed-collect
                         heap :max-regions 1 :min-garbage-ratio 0.0d0)))
            (expect (length result) :to-be 1)
            (expect (getf (first result) :status) :to-be :failed)
            (expect (cl-cc/runtime::rt-heap-region-evacuation-failed-p region)
                    :to-be-truthy)))))))
