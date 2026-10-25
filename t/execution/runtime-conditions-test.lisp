(in-package :cl-cc/runtime/execution/test)

(it-sequential
  "rt-register-function installs a global function definition."
  (cl-cc/runtime/execution:rt-register-function
    'rt-cond-test-triple
    (lambda (x)
      (* 3 x)))
  (expect (funcall 'rt-cond-test-triple 4) :to-equal 12))

(it-sequential
  "Storing and looking up code updates hit/miss counters and occupancy."
  (let ((cache (make-rt-code-cache :capacity 100)))
    (expect (cl-cc/runtime/execution:rt-code-cache-lookup 'f1 cache) :to-be-null)
    (cl-cc/runtime/execution:rt-code-cache-store 'f1 :code-1 :size 10 :cache cache)
    (expect (cl-cc/runtime/execution:rt-code-cache-lookup 'f1 cache) :to-be :code-1)
    (let ((stats (cl-cc/runtime/execution:rt-code-cache-stats cache)))
      (expect (getf stats :hits) :to-equal 1)
      (expect (getf stats :misses) :to-equal 1)
      (expect (getf stats :size) :to-equal 10)
      (expect (getf stats :entries) :to-equal 1))))

(it-sequential
  "rt-code-cache-evict removes an entry and decrements occupancy."
  (let ((cache (make-rt-code-cache :capacity 100)))
    (cl-cc/runtime/execution:rt-code-cache-store 'g :code-g :size 4 :cache cache)
    (expect (cl-cc/runtime/execution:rt-code-cache-evict 'g cache) :to-be-truthy)
    (expect (cl-cc/runtime/execution:rt-code-cache-lookup 'g cache) :to-be-null)
    (expect (getf (cl-cc/runtime/execution:rt-code-cache-stats cache) :size) :to-equal 0)))

(it-sequential
  "Storing beyond capacity evicts the coldest entry."
  (let ((cache (make-rt-code-cache :capacity 10)))
    (cl-cc/runtime/execution:rt-code-cache-store 'a :code-a :size 6 :cache cache)
    (cl-cc/runtime/execution:rt-code-cache-store 'b :code-b :size 6 :cache cache)
    (expect
      (plusp (getf (cl-cc/runtime/execution:rt-code-cache-stats cache) :evictions))
      :to-be-truthy)
    (expect (cl-cc/runtime/execution:rt-code-cache-lookup 'a cache) :to-be-null)
    (expect (cl-cc/runtime/execution:rt-code-cache-lookup 'b cache) :to-be :code-b)))

(it-sequential
  "rt-gc-unload-code removes a cache entry by function-entry key or by code value."
  (let ((cache (make-rt-code-cache :capacity 100)))
    (cl-cc/runtime/execution:rt-code-cache-store 'k1 :code-k1 :size 3 :cache cache)
    (expect (cl-cc/runtime/execution:rt-gc-unload-code nil 'k1 cache) :to-be-truthy)
    (expect (cl-cc/runtime/execution:rt-code-cache-lookup 'k1 cache) :to-be-null)
    (cl-cc/runtime/execution:rt-code-cache-store 'k2 :shared-code :size 2 :cache cache)
    (let ((removed (cl-cc/runtime/execution:rt-gc-unload-code nil :shared-code cache)))
      (expect removed :to-be-truthy)
      (expect (cl-cc/runtime/execution:rt-code-cache-lookup 'k2 cache) :to-be-null))))
