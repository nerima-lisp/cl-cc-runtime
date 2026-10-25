(in-package :cl-cc/runtime/memory/test)

(defun %make-small-heap ()
  "Create a minimal heap: 32-word young space (16 per semi), 32-word old space."
  (cl-cc/runtime/memory:make-rt-heap :young-size 32 :old-size 32))

(defun %write-header (heap addr size tag &optional (age 0))
  "Write a freshly made header at ADDR."
  (cl-cc/runtime/memory:rt-heap-set-header
   heap addr
   (cl-cc/runtime/memory:make-rt-header size tag :gc-bits age)))

(it-sequential "gc-header-field-roundtrip size"
  (destructuring-bind (h accessor expected) (list (cl-cc/runtime/memory:make-rt-header 7 1 :gc-bits 0) #'cl-cc/runtime/memory:rt-header-size 7)
    (expect (= expected (funcall accessor h)) :to-be-truthy)))

(it-sequential "gc-header-field-roundtrip tag"
  (destructuring-bind (h accessor expected) (list (cl-cc/runtime/memory:make-rt-header 3 5 :gc-bits 0) #'cl-cc/runtime/memory:rt-header-type-tag 5)
    (expect (= expected (funcall accessor h)) :to-be-truthy)))

(it-sequential "gc-header-field-roundtrip age"
  (destructuring-bind (h accessor expected) (list (cl-cc/runtime/memory:make-rt-header 3 1 :gc-bits 2) #'cl-cc/runtime/memory:rt-header-age 2)
    (expect (= expected (funcall accessor h)) :to-be-truthy)))

(it-sequential "gc-header-bit-toggles"
  (let ((h (cl-cc/runtime/memory:make-rt-header 3 1 :gc-bits 0)))
    ;; mark bit
    (let* ((hm (cl-cc/runtime/memory:header-set-mark h))
           (hu (cl-cc/runtime/memory:header-clear-mark hm)))
      (expect (cl-cc/runtime/memory:header-marked-p hm) :to-be-truthy)
      (expect (cl-cc/runtime/memory:header-marked-p h) :to-be-falsy)
      (expect (cl-cc/runtime/memory:header-marked-p hu) :to-be-falsy))
    ;; gray bit
    (let* ((hg (cl-cc/runtime/memory:header-set-gray h))
           (hu (cl-cc/runtime/memory:header-clear-gray hg)))
      (expect (cl-cc/runtime/memory:header-gray-p hg) :to-be-truthy)
      (expect (cl-cc/runtime/memory:header-gray-p h) :to-be-falsy)
      (expect (cl-cc/runtime/memory:header-gray-p hu) :to-be-falsy))))

(it-sequential "gc-header-forwarding-cases not-forwarding"
  (destructuring-bind (expect-fwd fwd-ptr plain-header target-addr) (list nil nil (cl-cc/runtime/memory:make-rt-header 3 1 :gc-bits 0) nil)
    (if expect-fwd
      (let ((fwd (cl-cc/runtime/memory:header-make-forwarding-ptr target-addr)))
        (expect (cl-cc/runtime/memory:header-forwarding-p fwd) :to-be-truthy)
        (expect (= target-addr (cl-cc/runtime/memory:header-forwarding-ptr fwd)) :to-be-truthy))
      (expect (cl-cc/runtime/memory:header-forwarding-p plain-header) :to-be-falsy))))

(it-sequential "gc-header-forwarding-cases forwarding-ptr"
  (destructuring-bind (expect-fwd fwd-ptr plain-header target-addr) (list t nil nil 42)
    (if expect-fwd
      (let ((fwd (cl-cc/runtime/memory:header-make-forwarding-ptr target-addr)))
        (expect (cl-cc/runtime/memory:header-forwarding-p fwd) :to-be-truthy)
        (expect (= target-addr (cl-cc/runtime/memory:header-forwarding-ptr fwd)) :to-be-truthy))
      (expect (cl-cc/runtime/memory:header-forwarding-p plain-header) :to-be-falsy))))

(it-sequential "rt-header-increment-age increment"
  (destructuring-bind (start-age expected) (list 1 2)
    (let* ((h  (cl-cc/runtime/memory:make-rt-header 3 1 :gc-bits start-age))
         (h2 (cl-cc/runtime/memory:rt-header-increment-age h)))
    (expect (= expected (cl-cc/runtime/memory:rt-header-age h2)) :to-be-truthy))))

(it-sequential "rt-header-increment-age cap-at-3"
  (destructuring-bind (start-age expected) (list 3 3)
    (let* ((h  (cl-cc/runtime/memory:make-rt-header 3 1 :gc-bits start-age))
         (h2 (cl-cc/runtime/memory:rt-header-increment-age h)))
    (expect (= expected (cl-cc/runtime/memory:rt-header-age h2)) :to-be-truthy))))

(it-sequential "gc-heap-creation-layout 32-word-young"
  (destructuring-bind (heap expected-from expected-to expected-old) (list (cl-cc/runtime/memory:make-rt-heap :young-size 32 :old-size 32) 0 16 32)
    (expect (= expected-from (cl-cc/runtime/memory:rt-heap-young-from-base heap)) :to-be-truthy) (expect (= expected-to (cl-cc/runtime/memory:rt-heap-young-to-base heap)) :to-be-truthy) (expect (= expected-old (cl-cc/runtime/memory:rt-heap-old-base heap)) :to-be-truthy)))

(it-sequential "gc-heap-creation-layout 16-word-young"
  (destructuring-bind (heap expected-from expected-to expected-old) (list (cl-cc/runtime/memory:make-rt-heap :young-size 16 :old-size 16) 0 8 16)
    (expect (= expected-from (cl-cc/runtime/memory:rt-heap-young-from-base heap)) :to-be-truthy) (expect (= expected-to (cl-cc/runtime/memory:rt-heap-young-to-base heap)) :to-be-truthy) (expect (= expected-old (cl-cc/runtime/memory:rt-heap-old-base heap)) :to-be-truthy)))

(it-sequential "gc-alloc-sequential-addresses-and-free-pointer"
  (let* ((heap (%make-small-heap))
         (addr1 (cl-cc/runtime/memory:rt-gc-alloc heap cl-cc/runtime/values:+rt-tag-cons+ 3)))
    (expect (= 0 addr1) :to-be-truthy)
    (expect (= 3 (cl-cc/runtime/memory:rt-heap-young-free heap)) :to-be-truthy)
    (let ((addr2 (cl-cc/runtime/memory:rt-gc-alloc heap cl-cc/runtime/values:+rt-tag-cons+ 3)))
      (expect (= 3 addr2) :to-be-truthy))))

(it-sequential "rt-alloc-header-size-readable"
  (let* ((heap (%make-small-heap))
         (addr (cl-cc/runtime/memory:rt-gc-alloc heap cl-cc/runtime/values:+rt-tag-cons+ 3)))
    (%write-header heap addr 3 cl-cc/runtime/values:+rt-tag-cons+)
    (expect (= 3 (cl-cc/runtime/memory:rt-heap-object-size heap addr)) :to-be-truthy)))

(it-sequential "gc-minor-gc-collects-and-updates-root"
  (let* ((heap (%make-small-heap)))
    (let ((addr1 (cl-cc/runtime/memory:rt-gc-alloc heap cl-cc/runtime/values:+rt-tag-cons+ 3))
          (addr2 (cl-cc/runtime/memory:rt-gc-alloc heap cl-cc/runtime/values:+rt-tag-cons+ 3)))
      (%write-header heap addr1 3 cl-cc/runtime/values:+rt-tag-cons+)
      (%write-header heap addr2 3 cl-cc/runtime/values:+rt-tag-cons+)
      ;; Only register addr1 as a root; addr2 is unreachable
      (let ((root (cons nil addr1)))
        (cl-cc/runtime/memory:rt-gc-add-root heap root)
        (cl-cc/runtime/memory:rt-gc-minor-collect heap)
        (expect (= 1 (cl-cc/runtime/memory:rt-heap-minor-gc-count heap)) :to-be-truthy)
        (expect (>= (cl-cc/runtime/memory:rt-heap-words-collected heap) 3) :to-be-truthy)
        (expect (cl-cc/runtime/memory:rt-young-addr-p heap (cdr root)) :to-be-truthy)
        (cl-cc/runtime/memory:rt-gc-remove-root heap root)))))

(it-sequential "gc-minor-gc-preserves-live-object-data"
  (let* ((heap (%make-small-heap)))
    (let ((addr (cl-cc/runtime/memory:rt-gc-alloc heap cl-cc/runtime/values:+rt-tag-cons+ 3)))
      (%write-header heap addr 3 cl-cc/runtime/values:+rt-tag-cons+)
      ;; Write slot values (non-pointer integers, safe for this test)
      (cl-cc/runtime/memory:rt-heap-set heap (+ addr 1) 111)
      (cl-cc/runtime/memory:rt-heap-set heap (+ addr 2) 222)
      (let ((root (cons nil addr)))
        (cl-cc/runtime/memory:rt-gc-add-root heap root)
        (cl-cc/runtime/memory:rt-gc-minor-collect heap)
        (let ((new-addr (cdr root)))
          (expect (= 111 (cl-cc/runtime/memory:rt-heap-ref heap (+ new-addr 1))) :to-be-truthy)
          (expect (= 222 (cl-cc/runtime/memory:rt-heap-ref heap (+ new-addr 2))) :to-be-truthy))
        (cl-cc/runtime/memory:rt-gc-remove-root heap root))))
  (let* ((heap (%make-small-heap)))
    (let ((addr (cl-cc/runtime/memory:rt-gc-alloc heap cl-cc/runtime/values:+rt-tag-string+ 3)))
      (%write-header heap addr 3 cl-cc/runtime/values:+rt-tag-string+)
      (let ((root (cons nil addr)))
        (cl-cc/runtime/memory:rt-gc-add-root heap root)
        (cl-cc/runtime/memory:rt-gc-minor-collect heap)
        (let* ((new-addr (cdr root))
               (new-hdr  (cl-cc/runtime/memory:rt-heap-object-header heap new-addr)))
          (expect (= cl-cc/runtime/values:+rt-tag-string+ (cl-cc/runtime/memory:rt-header-type-tag new-hdr)) :to-be-truthy))
        (cl-cc/runtime/memory:rt-gc-remove-root heap root)))))

(it-sequential "gc-promotion-promotes-old-object"
  (let* ((cl-cc/runtime/memory:*gc-tenuring-threshold* 3)
         (heap (cl-cc/runtime/memory:make-rt-heap :young-size 128 :old-size 64)))
    (let ((addr (cl-cc/runtime/memory:rt-gc-alloc heap cl-cc/runtime/values:+rt-tag-cons+ 3)))
      ;; Write header with age already at the tenuring threshold so the
      ;; very next minor GC will promote it.
      (cl-cc/runtime/memory:rt-heap-set-header
       heap addr
       (cl-cc/runtime/memory:make-rt-header 3 cl-cc/runtime/values:+rt-tag-cons+ :gc-bits 3))
      (let ((root (cons nil addr)))
        (cl-cc/runtime/memory:rt-gc-add-root heap root)
        (cl-cc/runtime/memory:rt-gc-minor-collect heap)
        ;; words-promoted must be > 0
        (expect (> (cl-cc/runtime/memory:rt-heap-words-promoted heap) 0) :to-be-truthy)
        ;; The object must now live in old space
        (expect (cl-cc/runtime/memory:rt-old-addr-p heap (cdr root)) :to-be-truthy)
        (cl-cc/runtime/memory:rt-gc-remove-root heap root)))))

(it-sequential "gc-write-barrier-card-dirty-behavior"
  (let* ((heap (cl-cc/runtime/memory:make-rt-heap :young-size 64 :old-size 64)))
    (let ((young-addr (cl-cc/runtime/memory:rt-gc-alloc heap cl-cc/runtime/values:+rt-tag-cons+ 3)))
      (%write-header heap young-addr 3 cl-cc/runtime/values:+rt-tag-cons+)
      (let* ((old-addr (cl-cc/runtime/memory:rt-heap-old-base heap)))
        (%write-header heap old-addr 3 cl-cc/runtime/values:+tag-other+)
        (setf (cl-cc/runtime/memory:rt-heap-old-free heap) (+ old-addr 3))
        (expect (cl-cc/runtime/memory:rt-card-dirty-p heap old-addr) :to-be-falsy)
        (cl-cc/runtime/memory:rt-gc-write-barrier heap old-addr 1 young-addr)
        (expect (cl-cc/runtime/memory:rt-card-dirty-p heap old-addr) :to-be-truthy)
        (expect (= young-addr (cl-cc/runtime/memory:rt-heap-ref heap (+ old-addr 1))) :to-be-truthy))))
  (let* ((heap (cl-cc/runtime/memory:make-rt-heap :young-size 64 :old-size 64)))
    (let* ((old-base (cl-cc/runtime/memory:rt-heap-old-base heap))
           (obj1     old-base)
           (obj2     (+ old-base 3)))
      (%write-header heap obj1 3 cl-cc/runtime/values:+tag-other+)
      (%write-header heap obj2 3 cl-cc/runtime/values:+tag-other+)
      (setf (cl-cc/runtime/memory:rt-heap-old-free heap) (+ old-base 6))
      (cl-cc/runtime/memory:rt-gc-write-barrier heap obj1 1 obj2)
      (expect (cl-cc/runtime/memory:rt-card-dirty-p heap obj1) :to-be-falsy))))

(it-sequential "gc-empty-minor-collection-completes"
  (let ((heap (%make-small-heap)))
    (cl-cc/runtime/memory:rt-gc-minor-collect heap)
    (expect (= 1 (cl-cc/runtime/memory:rt-heap-minor-gc-count heap))
            :to-be-truthy)))

(it-sequential "gc-empty-minor-collection-does-not-advance-free-pointer"
  (let* ((heap (%make-small-heap))
         (to-base (cl-cc/runtime/memory:rt-heap-young-to-base heap)))
    (cl-cc/runtime/memory:rt-gc-minor-collect heap)
    (expect (= to-base (cl-cc/runtime/memory:rt-heap-young-free heap))
            :to-be-truthy)))

(it-sequential "gc-clean-heap-has-no-dirty-cards"
  (let* ((heap (%make-small-heap))
         (old-base (cl-cc/runtime/memory:rt-heap-old-base heap)))
    (expect (cl-cc/runtime/memory:rt-card-dirty-p heap old-base)
            :to-be-falsy)))

(it-sequential "gc-default-heap-configuration-within-clamp-bounds"
  (let ((saved-young cl-cc/runtime/memory:*gc-young-size-words*)
        (saved-old cl-cc/runtime/memory:*gc-old-size-words*))
    (unwind-protect
        (let ((heap (cl-cc/runtime/memory:make-rt-heap)))
          (expect (>= cl-cc/runtime/memory:*gc-young-size-words* (floor (* 1 1024 1024) 8)) :to-be-truthy)
          (expect (<= cl-cc/runtime/memory:*gc-young-size-words* (floor (* 4 1024 1024) 8)) :to-be-truthy)
          (expect (>= cl-cc/runtime/memory:*gc-old-size-words* (floor (* 4 1024 1024) 8)) :to-be-truthy)
          (expect (<= cl-cc/runtime/memory:*gc-old-size-words* (floor (* 16 1024 1024) 8)) :to-be-truthy)
          (expect (= (* 2 (cl-cc/runtime/memory:rt-heap-young-semi-size heap))
                     cl-cc/runtime/memory:*gc-young-size-words*)
                  :to-be-truthy)
          (expect (= (cl-cc/runtime/memory:rt-heap-old-size heap)
                     cl-cc/runtime/memory:*gc-old-size-words*)
                  :to-be-truthy))
      (setf cl-cc/runtime/memory:*gc-young-size-words* saved-young
            cl-cc/runtime/memory:*gc-old-size-words* saved-old))))

(it-sequential "gc-default-heap-configuration-does-not-exceed-caps"
  (let ((saved-young cl-cc/runtime/memory:*gc-young-size-words*)
        (saved-old cl-cc/runtime/memory:*gc-old-size-words*))
    (unwind-protect
        (let ((heap (cl-cc/runtime/memory:make-rt-heap)))
          (expect (<= cl-cc/runtime/memory:*gc-young-size-words* (floor (* 4 1024 1024) 8)) :to-be-truthy)
          (expect (<= cl-cc/runtime/memory:*gc-old-size-words* (floor (* 16 1024 1024) 8)) :to-be-truthy)
          (expect (= (* 2 (cl-cc/runtime/memory:rt-heap-young-semi-size heap))
                     cl-cc/runtime/memory:*gc-young-size-words*)
                  :to-be-truthy)
          (expect (= (cl-cc/runtime/memory:rt-heap-old-size heap)
                     cl-cc/runtime/memory:*gc-old-size-words*)
                  :to-be-truthy))
      (setf cl-cc/runtime/memory:*gc-young-size-words* saved-young
            cl-cc/runtime/memory:*gc-old-size-words* saved-old))))

(it-sequential "gc-default-heap-stats-expose-public-keys"
  (let ((saved-young cl-cc/runtime/memory:*gc-young-size-words*)
        (saved-old cl-cc/runtime/memory:*gc-old-size-words*))
    (unwind-protect
        (let* ((heap (cl-cc/runtime/memory:make-rt-heap))
               (stats (cl-cc/runtime/memory:rt-gc-stats heap)))
          (expect (member :minor-gc-count stats) :to-be-truthy)
          (expect (member :young-total stats) :to-be-truthy)
          (expect (member :old-total stats) :to-be-truthy))
      (setf cl-cc/runtime/memory:*gc-young-size-words* saved-young
            cl-cc/runtime/memory:*gc-old-size-words* saved-old))))
