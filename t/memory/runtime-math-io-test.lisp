(in-package :cl-cc/runtime/memory/test)

(it-sequential
  "Runtime hash tables default to non-weak mode."
  (let ((h (cl-cc/runtime/values:rt-make-hash-table)))
    (expect (cl-cc/runtime/values:rt-hash-table-weakness h) :to-be-null)))

(it-sequential
  "A weak hash table records its weakness mode and stores metadata entries."
  (let ((cl-cc/runtime/values:*rt-weak-hash-table-registry* nil))
    (let ((wh (cl-cc/runtime/values:rt-make-hash-table :test #'eq :weakness :key)))
      (expect (cl-cc/runtime/values:rt-weak-hash-table-p wh) :to-be-truthy)
      (expect (cl-cc/runtime/values:rt-hash-table-weakness wh) :to-be :key)
      (cl-cc/runtime/values:rt-sethash 'wk wh 7)
      (expect (cl-cc/runtime/values:rt-gethash 'wk wh) :to-equal 7)
      (expect (cl-cc/runtime/values:rt-hash-count wh) :to-equal 1)
      (cl-cc/runtime/values:rt-remhash 'wk wh)
      (expect (cl-cc/runtime/values:rt-hash-count wh) :to-equal 0))))
