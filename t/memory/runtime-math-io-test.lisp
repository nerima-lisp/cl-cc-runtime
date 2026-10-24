(in-package :cl-cc/runtime/memory/test)

(it-sequential
  "An ordinary hash table reports NIL weakness."
  (let ((h (cl-cc/runtime::rt-make-hash-table)))
    (expect (cl-cc/runtime::rt-hash-table-weakness h) :to-be-null)))

(it-sequential
  "A weak hash table records its weakness mode and stores metadata entries."
  (let ((cl-cc/runtime::*rt-weak-hash-table-registry* nil))
    (let ((wh (cl-cc/runtime::rt-make-hash-table :test #'eq :weakness :key)))
      (expect (cl-cc/runtime::rt-weak-hash-table-p wh) :to-be-truthy)
      (expect (cl-cc/runtime::rt-hash-table-weakness wh) :to-be :key)
      (cl-cc/runtime::rt-sethash 'wk wh 7)
      (expect (cl-cc/runtime::rt-gethash 'wk wh) :to-equal 7)
      (expect (cl-cc/runtime::rt-hash-count wh) :to-equal 1)
      (cl-cc/runtime::rt-remhash 'wk wh)
      (expect (cl-cc/runtime::rt-hash-count wh) :to-equal 0))))
