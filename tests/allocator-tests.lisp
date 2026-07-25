;;;; tests/allocator-tests.lisp — arena / object-pool / size-class allocators (src/allocator.lisp).
(in-package :cl-cc-runtime/test)

(describe "arena allocator (allocator.lisp)"
  (it "a fresh arena has a zero cursor"
    (let ((a (cl-cc/runtime::make-arena :size-hint 16)))
      (expect (cl-cc/runtime::rt-arena-cursor a) :to-be 0)))

  (it "arena-alloc returns a block whose offset is the pre-alloc cursor"
    (let ((a (cl-cc/runtime::make-arena :size-hint 64)))
      (let ((b (cl-cc/runtime::arena-alloc a 8)))
        (expect (cl-cc/runtime::rt-arena-block-offset b) :to-be 0)
        (expect (cl-cc/runtime::rt-arena-block-size b) :to-be 8)
        (expect (cl-cc/runtime::rt-arena-cursor a) :to-be 8))))

  (it "sequential allocations bump the cursor and hand out contiguous offsets"
    (let ((a (cl-cc/runtime::make-arena :size-hint 64)))
      (let ((b0 (cl-cc/runtime::arena-alloc a 4))
            (b1 (cl-cc/runtime::arena-alloc a 6))
            (b2 (cl-cc/runtime::arena-alloc a 2)))
        (expect (cl-cc/runtime::rt-arena-block-offset b0) :to-be 0)
        (expect (cl-cc/runtime::rt-arena-block-offset b1) :to-be 4)
        (expect (cl-cc/runtime::rt-arena-block-offset b2) :to-be 10)
        (expect (cl-cc/runtime::rt-arena-cursor a) :to-be 12))))

  (it "arena-alloc grows the backing buffer when the request exceeds size-hint"
    (let ((a (cl-cc/runtime::make-arena :size-hint 4)))
      (cl-cc/runtime::arena-alloc a 100)
      (expect (>= (length (cl-cc/runtime::rt-arena-buffer a)) 100) :to-be-truthy)
      (expect (cl-cc/runtime::rt-arena-cursor a) :to-be 100)))

  (it "arena-reset rewinds the cursor to zero and reuses offsets"
    (let ((a (cl-cc/runtime::make-arena :size-hint 32)))
      (cl-cc/runtime::arena-alloc a 10)
      (cl-cc/runtime::arena-reset a)
      (expect (cl-cc/runtime::rt-arena-cursor a) :to-be 0)
      (expect (cl-cc/runtime::rt-arena-block-offset (cl-cc/runtime::arena-alloc a 3))
              :to-be 0)))

  (it "with-arena binds a usable arena for the dynamic extent of the body"
    (cl-cc/runtime::with-arena (arena :size-hint 8)
      (expect (cl-cc/runtime::rt-arena-p arena) :to-be-truthy)
      (expect (cl-cc/runtime::rt-arena-block-size (cl-cc/runtime::arena-alloc arena 5))
              :to-be 5)))

  (it-property "the cursor equals the running sum of every allocation size"
      ((sizes (gen-list (gen-integer :min 1 :max 64) :max-length 30)))
    (let ((a (cl-cc/runtime::make-arena :size-hint 8))
          (running 0))
      (dolist (s sizes)
        (expect (cl-cc/runtime::rt-arena-block-offset (cl-cc/runtime::arena-alloc a s))
                :to-be running)
        (incf running s))
      (expect (cl-cc/runtime::rt-arena-cursor a) :to-be running))))

(describe "object pool (allocator.lisp)"
  (it "make-object-pool pre-populates min-size objects"
    (let* ((n 0)
           (p (cl-cc/runtime::make-object-pool :seeded
                                               :min-size 3
                                               :constructor (lambda () (incf n)))))
      (declare (ignore p))
      (expect n :to-be 3)))

  (it "pool-acquire on an empty pool calls the constructor"
    (let ((p (cl-cc/runtime::make-object-pool :fresh
                                              :constructor (lambda () :made))))
      (expect (cl-cc/runtime::pool-acquire p) :to-be :made)))

  (it "release then acquire returns the released object (LIFO reuse)"
    (let ((p (cl-cc/runtime::make-object-pool :reuse
                                              :constructor (lambda () :new))))
      (let ((obj (list 'unique)))
        (cl-cc/runtime::pool-release p obj)
        (expect (cl-cc/runtime::pool-acquire p) :to-be obj))))

  (it "pool-release stops retaining objects once max-size is reached"
    (let ((p (cl-cc/runtime::make-object-pool :capped :max-size 2
                                              :constructor (lambda () :new))))
      (cl-cc/runtime::pool-release p :a)
      (cl-cc/runtime::pool-release p :b)
      (cl-cc/runtime::pool-release p :c) ; dropped, pool already full
      (expect (length (cl-cc/runtime::rt-object-pool-pool p)) :to-be 2)))

  (it "pool-release returns no values"
    (let ((p (cl-cc/runtime::make-object-pool :novalue
                                              :constructor (lambda () nil))))
      (expect (multiple-value-list (cl-cc/runtime::pool-release p :x)) :to-equal nil))))

(describe "size-class helpers (allocator.lisp)"
  (it "rt-alloc returns a zero-filled (unsigned-byte 8) vector of the requested size"
    (let ((v (cl-cc/runtime::rt-alloc 5)))
      (expect (length v) :to-be 5)
      (expect (every #'zerop v) :to-be-truthy)
      (expect (typep v '(simple-array (unsigned-byte 8) (*))) :to-be-truthy)))

  (it "rt-alloc of zero words still yields at least one byte"
    (expect (length (cl-cc/runtime::rt-alloc 0)) :to-be 1))

  (it "rt-free is a no-op returning nil"
    (expect (cl-cc/runtime::rt-free (cl-cc/runtime::rt-alloc 4) 4) :to-be-null))

  (it "rt-allocator-init returns t"
    (expect (cl-cc/runtime::rt-allocator-init) :to-be-truthy))

  ;; rt-size-class-for returns the smallest size class that can hold SIZE.
  (it "rt-size-class-for rounds a below-minimum size up to the smallest class"
    (expect (cl-cc/runtime::rt-size-class-for 4) :to-be 8))
  (it "rt-size-class-for returns 8 for the smallest size class exactly"
    (expect (cl-cc/runtime::rt-size-class-for 8) :to-be 8))
  (it "rt-size-class-for rounds up to the next class when between two"
    (expect (cl-cc/runtime::rt-size-class-for 1000) :to-be 1024))
  (it "rt-size-class-for returns the exact class when size matches one"
    (expect (cl-cc/runtime::rt-size-class-for 4096) :to-be 4096))
  (it "rt-size-class-for returns the large threshold above every class"
    (expect (cl-cc/runtime::rt-size-class-for 5000)
            :to-be cl-cc/runtime::+alloc-large-threshold+)))
