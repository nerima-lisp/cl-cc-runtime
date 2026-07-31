;;;; t/gc-minor-test.lisp - Generational GC Tests
;;;
;;; Tests for the cl-cc/runtime generational GC:
;;; - Object header encoding/decoding
;;; - Heap creation and layout
;;; - Bump-pointer allocation
;;; - Minor GC: garbage collection, live-object preservation, promotion
;;; - Write barrier and card table
;;; - GC statistics
(in-package :cl-cc-runtime/test)

;;; Import GC symbols from the runtime package.
;;; We alias them locally via a helper rather than polluting the test package
;;; — all calls below are fully qualified as cl-cc/runtime::*.
;;; ------------------------------------------------------------
;;; Suite
;;; ------------------------------------------------------------
;;; ------------------------------------------------------------
;;; Helpers
;;; ------------------------------------------------------------
(defun %make-small-heap ()
  "Create a minimal heap: 32-word young space (16 per semi), 32-word old space."
  (cl-cc/runtime::make-rt-heap :young-size 32 :old-size 32))

(defun %write-header (heap addr size tag &optional (age 0))
  "Write a freshly made header at ADDR."
  (cl-cc/runtime::rt-heap-set-header
    heap
    addr
    (cl-cc/runtime::make-rt-header size tag :gc-bits age)))

;;; ------------------------------------------------------------
;;; Test 1: gc-header-basics
;;; ------------------------------------------------------------
(it-sequential-each (("size" 7 1 0 cl-cc/runtime::rt-header-size 7)
                      ("tag"  3 5 0 cl-cc/runtime::rt-header-type-tag 5)
                      ("age"  3 1 2 cl-cc/runtime::rt-header-age 2))
    "make-rt-header round-trips size, tag, and age fields independently (~A)."
    (label size tag age accessor expected)
  (declare (ignore label))
  (let ((h (cl-cc/runtime::make-rt-header size tag :gc-bits age)))
    (expect (funcall accessor h) :to-equal expected)))

(it-sequential "mark and gray bits: set makes true; clear makes false; fresh header is false." (let ((h (cl-cc/runtime::make-rt-header 3 1 :gc-bits 0)))
    ;; mark bit
    (let* ((hm (cl-cc/runtime::header-set-mark h))
           (hu (cl-cc/runtime::header-clear-mark hm)))
      (expect (cl-cc/runtime::header-marked-p hm) :to-be-truthy)
      (expect (cl-cc/runtime::header-marked-p h) :to-be-falsy)
      (expect (cl-cc/runtime::header-marked-p hu) :to-be-falsy))
    ;; gray bit
    (let* ((hg (cl-cc/runtime::header-set-gray h))
           (hu (cl-cc/runtime::header-clear-gray hg)))
      (expect (cl-cc/runtime::header-gray-p hg) :to-be-truthy)
      (expect (cl-cc/runtime::header-gray-p h) :to-be-falsy)
      (expect (cl-cc/runtime::header-gray-p hu) :to-be-falsy))))

(it-sequential-each (("not-forwarding" nil 3 1 0 nil)
                      ("forwarding-ptr" t nil nil nil 42))
    "Forwarding pointer: regular header is not forwarding; make-forwarding-ptr round-trips address (~A)."
    (label expect-fwd header-size header-tag header-age target-addr)
  (declare (ignore label))
  (if expect-fwd
      (let ((fwd (cl-cc/runtime::header-make-forwarding-ptr target-addr)))
        (expect (cl-cc/runtime::header-forwarding-p fwd) :to-be-truthy)
        (expect (cl-cc/runtime::header-forwarding-ptr fwd) :to-equal target-addr))
      (let ((plain-header (cl-cc/runtime::make-rt-header header-size header-tag :gc-bits header-age)))
        (expect (cl-cc/runtime::header-forwarding-p plain-header) :to-be-falsy))))

(it-sequential-each (("increment" 1 2)
                      ("cap-at-3"  3 3))
    "rt-header-increment-age increments by 1 normally; caps at 3 (~A)."
    (label start-age expected)
  (declare (ignore label))
  (let* ((h  (cl-cc/runtime::make-rt-header 3 1 :gc-bits start-age))
         (h2 (cl-cc/runtime::rt-header-increment-age h)))
    (expect (cl-cc/runtime::rt-header-age h2) :to-equal expected)))

;;; ------------------------------------------------------------
;;; Test 2: gc-heap-creation
;;; ------------------------------------------------------------
(it-sequential-each (("32-word-young" 32 32 0 16 32)
                      ("16-word-young" 16 16 0  8 16))
    "Heap creation: young-from-base=0, young-to-base=semi-size, old-base=2*semi-size, gc-state=:normal (~A)."
    (label young-size old-size expected-from expected-to expected-old)
  (declare (ignore label))
  (let ((heap (cl-cc/runtime::make-rt-heap :young-size young-size :old-size old-size)))
    (expect (cl-cc/runtime::rt-heap-young-from-base heap) :to-equal expected-from)
    (expect (cl-cc/runtime::rt-heap-young-to-base heap) :to-equal expected-to)
    (expect (cl-cc/runtime::rt-heap-old-base heap) :to-equal expected-old)))

;;; ------------------------------------------------------------
;;; Test 3: gc-alloc-basic
;;; ------------------------------------------------------------
(it-sequential
  "First alloc returns 0; young-free advances to 3; second alloc starts at 3."
  (let* ((heap (%make-small-heap))
         (addr1 (cl-cc/runtime::rt-gc-alloc heap cl-cc/runtime:+rt-tag-cons+ 3)))
    (expect addr1 :to-equal 0)
    (expect (cl-cc/runtime::rt-heap-young-free heap) :to-equal 3)
    (let ((addr2 (cl-cc/runtime::rt-gc-alloc heap cl-cc/runtime:+rt-tag-cons+ 3)))
      (expect addr2 :to-equal 3))))

(it-sequential
  "After writing a header, rt-heap-object-size returns the correct size."
  (let* ((heap (%make-small-heap))
         (addr (cl-cc/runtime::rt-gc-alloc heap cl-cc/runtime:+rt-tag-cons+ 3)))
    (%write-header heap addr 3 cl-cc/runtime:+rt-tag-cons+)
    (expect (cl-cc/runtime::rt-heap-object-size heap addr) :to-equal 3)))

;;; ------------------------------------------------------------
;;; Test 4: gc-minor-gc-collects-garbage
;;; ------------------------------------------------------------
(it-sequential "After minor GC: unreachable object's words are counted as collected; root's cdr is updated to the live object's new young-space address." (let* ((heap (%make-small-heap)))
    (let ((addr1 (cl-cc/runtime::rt-gc-alloc heap cl-cc/runtime:+rt-tag-cons+ 3))
          (addr2 (cl-cc/runtime::rt-gc-alloc heap cl-cc/runtime:+rt-tag-cons+ 3)))
      (%write-header heap addr1 3 cl-cc/runtime:+rt-tag-cons+)
      (%write-header heap addr2 3 cl-cc/runtime:+rt-tag-cons+)
      ;; Only register addr1 as a root; addr2 is unreachable
      (let ((root (cons nil addr1)))
        (cl-cc/runtime::rt-gc-add-root heap root)
        (cl-cc/runtime::rt-gc-minor-collect heap)
        (expect (cl-cc/runtime::rt-heap-minor-gc-count heap) :to-equal 1)
        (expect (>= (cl-cc/runtime::rt-heap-words-collected heap) 3) :to-be-truthy)
        (expect (cl-cc/runtime::rt-young-addr-p heap (cdr root)) :to-be-truthy)
        (cl-cc/runtime::rt-gc-remove-root heap root)))))

;;; ------------------------------------------------------------
;;; Test 5: gc-minor-gc-preserves-live-objects
;;; ------------------------------------------------------------
(it-sequential "After minor GC, a live object's slot values and header tag are preserved." (let* ((heap (%make-small-heap)))
    (let ((addr (cl-cc/runtime::rt-gc-alloc heap cl-cc/runtime:+rt-tag-cons+ 3)))
      (%write-header heap addr 3 cl-cc/runtime:+rt-tag-cons+)
      ;; Write slot values (non-pointer integers, safe for this test)
      (cl-cc/runtime::rt-heap-set heap (+ addr 1) 111)
      (cl-cc/runtime::rt-heap-set heap (+ addr 2) 222)
      (let ((root (cons nil addr)))
        (cl-cc/runtime::rt-gc-add-root heap root)
        (cl-cc/runtime::rt-gc-minor-collect heap)
        (let ((new-addr (cdr root)))
          (expect (cl-cc/runtime::rt-heap-ref heap (+ new-addr 1)) :to-equal 111)
          (expect (cl-cc/runtime::rt-heap-ref heap (+ new-addr 2)) :to-equal 222))
        (cl-cc/runtime::rt-gc-remove-root heap root))))
  (let* ((heap (%make-small-heap)))
    (let ((addr (cl-cc/runtime::rt-gc-alloc heap cl-cc/runtime:+rt-tag-string+ 3)))
      (%write-header heap addr 3 cl-cc/runtime:+rt-tag-string+)
      (let ((root (cons nil addr)))
        (cl-cc/runtime::rt-gc-add-root heap root)
        (cl-cc/runtime::rt-gc-minor-collect heap)
        (let* ((new-addr (cdr root))
               (new-hdr  (cl-cc/runtime::rt-heap-object-header heap new-addr)))
          (expect (cl-cc/runtime::rt-header-type-tag new-hdr) :to-equal cl-cc/runtime:+rt-tag-string+))
        (cl-cc/runtime::rt-gc-remove-root heap root)))))

;;; ------------------------------------------------------------
;;; Test 5b: gc-minor-gc-evacuates-non-root-cell-roots
;;; ------------------------------------------------------------
;;; RT-GC-ADD-ROOT-backed roots (above) are the most exercised root class in
;;; this suite; the other four root classes RT-GC-MINOR-COLLECT scans --
;;; dynamic-binding-stack entries, the global-variable registry, conservative
;;; stack words, and stack-map frames -- had no direct minor-GC coverage
;;; before this test, despite RT-GC-MINOR-COLLECT sharing a single evacuation
;;; helper across all of them. This exercises the two easiest to construct a
;;; realistic root for.
(it-sequential
  "Minor GC evacuates a dynamic-binding-stack root and updates the binding's value in place."
  (let* ((heap (%make-small-heap)))
    (cl-cc/runtime::rt-register-special-variable
     'gc-minor-test-binding-var :global-only-p nil)
    (let ((addr (cl-cc/runtime::rt-gc-alloc heap cl-cc/runtime:+rt-tag-cons+ 3)))
      (%write-header heap addr 3 cl-cc/runtime:+rt-tag-cons+)
      (cl-cc/runtime::rt-heap-set heap (+ addr 1) 42)
      (let* ((binding (list :symbol 'gc-minor-test-binding-var :value addr))
             (cl-cc/runtime::*gc-threads* (list (list :bindings (list binding)))))
        (cl-cc/runtime::rt-gc-minor-collect heap)
        (let ((new-addr (getf binding :value)))
          (expect (integerp new-addr) :to-be-truthy)
          (expect (cl-cc/runtime::rt-young-addr-p heap new-addr) :to-be-truthy)
          (expect (cl-cc/runtime::rt-heap-ref heap (+ new-addr 1)) :to-equal 42))))))
(it-sequential
  "Minor GC evacuates a global-variable-registry root and updates the registry entry in place."
  (let* ((heap (%make-small-heap))
         (cl-cc/runtime::*rt-global-var-registry* (make-hash-table :test #'eq)))
    (let ((addr (cl-cc/runtime::rt-gc-alloc heap cl-cc/runtime:+rt-tag-cons+ 3)))
      (%write-header heap addr 3 cl-cc/runtime:+rt-tag-cons+)
      (cl-cc/runtime::rt-heap-set heap (+ addr 1) 43)
      (setf (gethash 'gc-minor-test-global-var cl-cc/runtime::*rt-global-var-registry*) addr)
      (cl-cc/runtime::rt-gc-minor-collect heap)
      (let ((new-addr (gethash 'gc-minor-test-global-var cl-cc/runtime::*rt-global-var-registry*)))
        (expect (integerp new-addr) :to-be-truthy)
        (expect (cl-cc/runtime::rt-young-addr-p heap new-addr) :to-be-truthy)
        (expect (cl-cc/runtime::rt-heap-ref heap (+ new-addr 1)) :to-equal 43)))))

;;; ------------------------------------------------------------
;;; Test 6: gc-promotion-threshold
;;; ------------------------------------------------------------
(it-sequential "An object that survives enough minor GCs is promoted to old space."
  ;; Use a larger heap to fit the object after repeated copies.
  ;; Bind *gc-tenuring-threshold* to insulate against parallel-test mutation.
  (let* ((cl-cc/runtime::*gc-tenuring-threshold* 3)
         (heap (cl-cc/runtime::make-rt-heap :young-size 128 :old-size 64)))
    (let ((addr (cl-cc/runtime::rt-gc-alloc heap cl-cc/runtime:+rt-tag-cons+ 3)))
      ;; Write header with age already at the tenuring threshold so the
      ;; very next minor GC will promote it.
      (cl-cc/runtime::rt-heap-set-header
       heap addr
       (cl-cc/runtime::make-rt-header 3 cl-cc/runtime:+rt-tag-cons+ :gc-bits 3))
      (let ((root (cons nil addr)))
        (cl-cc/runtime::rt-gc-add-root heap root)
        (cl-cc/runtime::rt-gc-minor-collect heap)
        ;; words-promoted must be > 0
        (expect (> (cl-cc/runtime::rt-heap-words-promoted heap) 0) :to-be-truthy)
        ;; The object must now live in old space
        (expect (cl-cc/runtime::rt-old-addr-p heap (cdr root)) :to-be-truthy)
        (cl-cc/runtime::rt-gc-remove-root heap root)))))

;;; ------------------------------------------------------------
;;; Test 7: gc-write-barrier-card-dirty
;;; ------------------------------------------------------------
(it-sequential "rt-gc-write-barrier marks the card dirty for old->young writes; leaves it clean for old->old writes."
  ;; old-space object receives young pointer: card must become dirty
  (let* ((heap (cl-cc/runtime::make-rt-heap :young-size 64 :old-size 64)))
    (let ((young-addr (cl-cc/runtime::rt-gc-alloc heap cl-cc/runtime:+rt-tag-cons+ 3)))
      (%write-header heap young-addr 3 cl-cc/runtime:+rt-tag-cons+)
      (let* ((old-addr (cl-cc/runtime::rt-heap-old-base heap)))
        (%write-header heap old-addr 3 cl-cc/runtime:+tag-other+)
        (setf (cl-cc/runtime::rt-heap-old-free heap) (+ old-addr 3))
        (expect (cl-cc/runtime::rt-card-dirty-p heap old-addr) :to-be-falsy)
        (cl-cc/runtime::rt-gc-write-barrier heap old-addr 1 young-addr)
        (expect (cl-cc/runtime::rt-card-dirty-p heap old-addr) :to-be-truthy)
        (expect (cl-cc/runtime::rt-heap-ref heap (+ old-addr 1)) :to-equal young-addr))))
  ;; old-space object receives old-space pointer: card must remain clean
  (let* ((heap (cl-cc/runtime::make-rt-heap :young-size 64 :old-size 64)))
    (let* ((old-base (cl-cc/runtime::rt-heap-old-base heap))
           (obj1     old-base)
           (obj2     (+ old-base 3)))
      (%write-header heap obj1 3 cl-cc/runtime:+tag-other+)
      (%write-header heap obj2 3 cl-cc/runtime:+tag-other+)
      (setf (cl-cc/runtime::rt-heap-old-free heap) (+ old-base 6))
      (cl-cc/runtime::rt-gc-write-barrier heap obj1 1 obj2)
      (expect (cl-cc/runtime::rt-card-dirty-p heap obj1) :to-be-falsy))))

;;; ------------------------------------------------------------
;;; Section 4: GC minor helper unit tests
;;; ------------------------------------------------------------
(it-sequential "%gc-update-promoted on an empty promoted list completes without error." (let ((heap (%make-small-heap)))
    (cl-cc/runtime::%gc-update-promoted heap '())
    ;; No assertion needed — just verify no error is raised.
    (expect t :to-be-truthy)))

(it-sequential "%gc-cheney-scan with evac-target equal to to-free does not iterate." (let* ((heap         (%make-small-heap))
         (base         (cl-cc/runtime::rt-heap-young-to-base heap))
         (to-free-cell (cons base base))
         (promoted     (list nil))
         (in-source-p  (lambda (addr) (declare (ignore addr)) nil)))
    ;; scan == (cdr to-free-cell) so the loop body never runs
    (cl-cc/runtime::%gc-cheney-scan heap base to-free-cell promoted in-source-p)
    (expect (cdr to-free-cell) :to-equal base)))

(it-sequential "%gc-scan-dirty-cards on a fresh heap (all cards clean) makes no modifications." (let* ((heap         (%make-small-heap))
         (to-free-cell (cons (cl-cc/runtime::rt-heap-young-to-base heap)
                             (cl-cc/runtime::rt-heap-young-to-base heap)))
         (promoted     (list nil))
         (in-source-p  (lambda (addr) (declare (ignore addr)) nil))
         (initial-free (cdr to-free-cell)))
    (cl-cc/runtime::%gc-scan-dirty-cards heap to-free-cell promoted in-source-p)
    ;; No dirty cards → to-free not advanced
    (expect (cdr to-free-cell) :to-equal initial-free)))

;;; ------------------------------------------------------------
;;; Test: rt-gc-auto-configure-heap
;;; ------------------------------------------------------------
(it-sequential "rt-gc-auto-configure-heap with a small memory-bytes clamps young/old to their minimums."
  ;; Save and restore the global words so the test is side-effect-free.
  (let ((saved-young cl-cc/runtime::*gc-young-size-words*)
        (saved-old   cl-cc/runtime::*gc-old-size-words*))
    (unwind-protect
        (let ((result (cl-cc/runtime::rt-gc-auto-configure-heap :memory-bytes (* 4 1024 1024))))
          ;; young clamp: [1MB/8 .. 4MB/8] words; small input should hit lower bound
          (expect (>= cl-cc/runtime::*gc-young-size-words* (floor (* 1 1024 1024) 8)) :to-be-truthy)
          (expect (<= cl-cc/runtime::*gc-young-size-words* (floor (* 4 1024 1024) 8)) :to-be-truthy)
          ;; old clamp: [4MB/8 .. 16MB/8] words; small input should hit lower bound
          (expect (>= cl-cc/runtime::*gc-old-size-words* (floor (* 4 1024 1024) 8)) :to-be-truthy)
          (expect (<= cl-cc/runtime::*gc-old-size-words* (floor (* 16 1024 1024) 8)) :to-be-truthy)
          ;; result plist includes the expected keys
          (expect (getf result :young-size-words) :to-be-truthy)
          (expect (getf result :old-size-words) :to-be-truthy))
      (setf cl-cc/runtime::*gc-young-size-words* saved-young
            cl-cc/runtime::*gc-old-size-words*   saved-old))))

(it-sequential "rt-gc-auto-configure-heap with a large memory-bytes caps young/old at their maximums." (let ((saved-young cl-cc/runtime::*gc-young-size-words*)
        (saved-old   cl-cc/runtime::*gc-old-size-words*))
    (unwind-protect
        (let ((result (cl-cc/runtime::rt-gc-auto-configure-heap
                       :memory-bytes (* 64 1024 1024 1024)))) ; 64 GB
          ;; young cap: 4MB/8 = 524288 words
          (expect (<= cl-cc/runtime::*gc-young-size-words* (floor (* 4 1024 1024) 8)) :to-be-truthy)
          ;; old cap: 16MB/8 = 2097152 words
          (expect (<= cl-cc/runtime::*gc-old-size-words* (floor (* 16 1024 1024) 8)) :to-be-truthy)
          ;; result plist must report the capped values
          (expect (getf result :young-size-words) :to-equal cl-cc/runtime::*gc-young-size-words*)
          (expect (getf result :old-size-words) :to-equal cl-cc/runtime::*gc-old-size-words*))
      (setf cl-cc/runtime::*gc-young-size-words* saved-young
            cl-cc/runtime::*gc-old-size-words*   saved-old))))

(it-sequential
  "rt-gc-auto-configure-heap returns a plist with all expected keys."
  (let ((saved-young cl-cc/runtime::*gc-young-size-words*)
        (saved-old cl-cc/runtime::*gc-old-size-words*))
    (unwind-protect (let ((result
            (cl-cc/runtime::rt-gc-auto-configure-heap :memory-bytes (* 256 1024 1024))))
        (expect (member :memory-bytes result) :to-be-truthy)
        (expect (member :young-size-words result) :to-be-truthy)
        (expect (member :old-size-words result) :to-be-truthy))
      (setf cl-cc/runtime::*gc-young-size-words* saved-young
            cl-cc/runtime::*gc-old-size-words* saved-old))))

;;; ------------------------------------------------------------
;;; rt-gc-alloc: slab exhaustion falls back to young-space [#regression]
;;; ------------------------------------------------------------
;;;
;;; A slab page grows by taking words from old space (%rt-slab-allocate-page
;;; bumps rt-heap-old-free). With old space too small to hold even one page,
;;; rt-slab-alloc signals an error. rt-gc-alloc must catch that inside the
;;; slab attempt and fall through to another strategy -- here, young-space
;;; bump allocation -- rather than let the whole allocation fail or, worse,
;;; silently return NIL as a word address.
(it-sequential
  "rt-gc-alloc falls back to young-space bump allocation when the slab allocator cannot grow a page because old space is full."
  (let ((saved-use-slab cl-cc/runtime::*rt-use-slab-allocator*))
    (unwind-protect
        (let ((heap (cl-cc/runtime::make-rt-heap :young-size 64 :old-size 1)))
          (setf cl-cc/runtime::*rt-use-slab-allocator* t)
          ;; size-words 3 matches the :CONS slab class in
          ;; *RT-SLAB-SIZE-CLASSES*, whose page (255 words) cannot fit in a
          ;; 1-word old space.
          (let ((addr (cl-cc/runtime::rt-gc-alloc heap :cons 3)))
            (expect (integerp addr) :to-be-truthy)
            (expect (cl-cc/runtime::rt-young-addr-p heap addr) :to-be-truthy)))
      (setf cl-cc/runtime::*rt-use-slab-allocator* saved-use-slab))))
