;;;; t/gc-requirements-test.lisp - GC Feature Requirement Evidence Tests
;;;;
;;;; Tests for FR implementations in the cl-cc/runtime generational GC:
;;;; - FR-331: Old-Space Free-List Reuse
;;;; - FR-333: Nursery Sizing Heuristics
;;;; - FR-335: Write Barrier Young-to-Young Elision
;;;; - FR-336: GC-NaN-Boxing Integration
;;;; - FR-341: GC Pause Time Goals / SLO

(in-package :cl-cc-runtime/test)

;;; ------------------------------------------------------------
;;; Helpers
;;; ------------------------------------------------------------

(defun %make-small-heap-fr ()
  "Create a minimal heap: 64-word young space (32 per semi), 128-word old space."
  (cl-cc/runtime::make-rt-heap :young-size 64 :old-size 128))

(defun %fr-write-object (heap addr size tag &optional (age 0))
  "Write a header at ADDR and return the address."
  (cl-cc/runtime::rt-heap-set-header
   heap addr
   (cl-cc/runtime::make-rt-header size tag :gc-bits age))
  addr)

(defun %fr-assert-free-list-blocks (heap expected-blocks)
  (let ((blocks (cl-cc/runtime::rt-heap-free-list-blocks heap)))
    (expect (listp blocks) :to-be-truthy)
    (dolist (block expected-blocks)
      (expect (member block blocks :test #'equal) :to-be-truthy))))

(defun %fr-assert-pointer-tags (expected-tags)
  (dolist (case expected-tags)
    (destructuring-bind (addr tag) case
      (expect (cl-cc/runtime::pointer-tag
                 (cl-cc/runtime::encode-pointer addr tag)) :to-equal tag))))

(defun %fr-assert-header-fields (header expected-size expected-tag expected-age)
  (expect (typep header '(unsigned-byte 64)) :to-be-truthy)
  (expect (cl-cc/runtime::rt-header-size header) :to-equal expected-size)
  (expect (cl-cc/runtime::rt-header-type-tag header) :to-equal expected-tag)
  (expect (cl-cc/runtime::rt-header-age header) :to-equal expected-age))

;;; ------------------------------------------------------------
;;; FR-331: Old-Space Free-List Allocation Reuse
;;; ------------------------------------------------------------

(it-sequential "FR-331: The heap has segregated free-list bins (16 size classes)." (let ((heap (%make-small-heap-fr)))
    (let ((bins (cl-cc/runtime::rt-heap-free-bins heap)))
      (expect (vectorp bins) :to-be-truthy)
      (expect (length bins) :to-equal 16))))

(it-sequential "FR-331: Free-list insert and best-fit find reuse a block and retain the remainder." (let ((heap (%make-small-heap-fr)))
    (let ((insert-bin (cl-cc/runtime::rt-free-list-insert heap 8 1000)))
      (expect (integerp insert-bin) :to-be-truthy)
      (multiple-value-bind (bin addr) (cl-cc/runtime::rt-free-list-find heap 4)
        (expect bin :to-equal insert-bin)
        (expect addr :to-equal 1000)
        (%fr-assert-free-list-blocks heap (list (cons 4 1004)))))))

(it-sequential "FR-331: Free-list blocks can be enumerated across segregated bins." (let ((heap (%make-small-heap-fr)))
    (cl-cc/runtime::rt-free-list-insert heap 8 1000)
    (cl-cc/runtime::rt-free-list-insert heap 16 2000)
    (%fr-assert-free-list-blocks heap (list (cons 8 1000)
                                            (cons 16 2000)))))

(it-sequential "FR-331: Size classes map to monotonic power-of-2 bucket indices." (let ((bin-3  (cl-cc/runtime::rt-free-list-bin-index 3))
        (bin-4  (cl-cc/runtime::rt-free-list-bin-index 4))
        (bin-8  (cl-cc/runtime::rt-free-list-bin-index 8))
        (bin-32 (cl-cc/runtime::rt-free-list-bin-index 32))
        (bin-64 (cl-cc/runtime::rt-free-list-bin-index 64)))
    (expect bin-4 :to-equal bin-3)
    (expect (>= bin-32 bin-8) :to-be-truthy)
    (expect (>= bin-64 bin-32) :to-be-truthy)))

(it-sequential "FR-156: Segregated free-list allocation reuses the best fitting bin and splits remainders." (let ((heap (%make-small-heap-fr)))
    (cl-cc/runtime::rt-free-list-insert heap 16 100)
    (cl-cc/runtime::rt-free-list-insert heap 64 200)
    (multiple-value-bind (bin addr) (cl-cc/runtime::rt-free-list-find heap 12)
      (expect bin :to-equal (cl-cc/runtime::rt-free-list-bin-index 16))
      (expect addr :to-equal 100)
      (%fr-assert-free-list-blocks heap (list (cons 4 112))))))

;;; ------------------------------------------------------------
;;; FR-333: Nursery Sizing Heuristics
;;; ------------------------------------------------------------

(it-sequential "FR-333: High promotion ratio grows the default nursery for subsequently created heaps." (let ((cl-cc/runtime::*gc-young-size-words* 65536)
        (cl-cc/runtime::*rt-minor-gc-window-start* nil)
        (cl-cc/runtime::*rt-low-promotion-cycles* 0))
    (cl-cc/runtime::%rt-gc-tune-nursery 0.9d0)
    (expect cl-cc/runtime::*gc-young-size-words* :to-equal 131072)))

(it-sequential "FR-333: Sustained low promotion ratio shrinks the default nursery floor-aware." (let ((cl-cc/runtime::*gc-young-size-words* 65536)
        (cl-cc/runtime::*rt-minor-gc-window-start*
          (- (get-internal-real-time) (* 2 internal-time-units-per-second)))
        (cl-cc/runtime::*rt-low-promotion-cycles* 0))
    (cl-cc/runtime::%rt-gc-tune-nursery 0.01d0)
    (expect cl-cc/runtime::*gc-young-size-words* :to-equal 65536)
    (cl-cc/runtime::%rt-gc-tune-nursery 0.01d0)
    (expect cl-cc/runtime::*gc-young-size-words* :to-equal 65536)
    (cl-cc/runtime::%rt-gc-tune-nursery 0.01d0)
    (expect cl-cc/runtime::*gc-young-size-words* :to-equal 32768)))

;;; ------------------------------------------------------------
;;; FR-335: Write Barrier Young-to-Young Elision
;;; ------------------------------------------------------------

(it-sequential "FR-335: Young-to-young stores update the slot without dirtying cards or SATB queues." (let ((heap (%make-small-heap-fr)))
    (let ((obj-addr (cl-cc/runtime::rt-gc-alloc heap cl-cc/runtime:+rt-tag-cons+ 3))
          (target   (cl-cc/runtime::rt-gc-alloc heap cl-cc/runtime:+rt-tag-cons+ 3)))
      (%fr-write-object heap obj-addr 3 cl-cc/runtime:+rt-tag-cons+)
      (%fr-write-object heap target 3 cl-cc/runtime:+rt-tag-cons+)
      (setf (cl-cc/runtime::rt-heap-gc-state heap) :major-gc)
      (cl-cc/runtime::rt-gc-write-barrier heap obj-addr 1 target)
      (expect (cl-cc/runtime::rt-heap-ref heap (+ obj-addr 1)) :to-equal target)
      (expect (find-if-not #'zerop (cl-cc/runtime::rt-heap-card-table heap)) :to-be-falsy)
      (expect (length (cl-cc/runtime::rt-heap-satb-queue heap)) :to-equal 0))))

(it-sequential "FR-335: Barrier buffer flush marks queued old cards and clears the buffer." (let ((heap (%make-small-heap-fr)))
    (let ((old-addr (cl-cc/runtime::rt-heap-old-base heap)))
      (push old-addr (cl-cc/runtime::rt-heap-barrier-buffer heap))
      (expect (cl-cc/runtime::rt-card-dirty-p heap old-addr) :to-be-falsy)
      (cl-cc/runtime::rt-gc-flush-barrier-buffer heap)
      (expect (cl-cc/runtime::rt-card-dirty-p heap old-addr) :to-be-truthy)
      (expect (length (cl-cc/runtime::rt-heap-barrier-buffer heap)) :to-equal 0))))

;;; ------------------------------------------------------------
;;; FR-336: GC-NaN-Boxing Integration
;;; ------------------------------------------------------------

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

(it-sequential "FR-266: Object headers pack size/tag/age metadata into one unsigned 64-bit word." (let ((header (cl-cc/runtime::make-rt-header 42 cl-cc/runtime:+rt-tag-cons+ :gc-bits 2)))
    (%fr-assert-header-fields header 42 cl-cc/runtime:+rt-tag-cons+ 2)))

(it-sequential "FR-184: Weak references clear unreachable referents and finalizers run for unmarked objects." (let* ((heap (%make-small-heap-fr))
         (marked (make-hash-table :test #'eql))
         (referent (cl-cc/runtime::encode-pointer (cl-cc/runtime::rt-heap-old-base heap)
                                                  cl-cc/runtime:+tag-object+))
         (weak (cl-cc/runtime::rt-make-weak-ref referent))
         (object-addr (cl-cc/runtime::rt-heap-old-base heap))
         (finalized nil)
         (cl-cc/runtime::*rt-reference-registry* (list weak))
         (cl-cc/runtime::*rt-finalizer-registry* nil)
         (cl-cc/runtime::*rt-finalization-queue* nil))
    (cl-cc/runtime::rt-heap-set-header
     heap (cl-cc/runtime::rt-heap-old-base heap)
     (cl-cc/runtime::make-rt-header 1 cl-cc/runtime:+rt-tag-cons+ :gc-bits 0))
    (cl-cc/runtime::%rt-gc-process-weak-references heap marked)
    (expect (cl-cc/runtime::rt-ref-get weak) :to-be-null)
    (cl-cc/runtime::register-finalizer object-addr (lambda (obj) (setf finalized obj)))
    (cl-cc/runtime::%rt-gc-process-finalizers heap marked)
    ;; After GC processing, object is queued but not yet executed
    (expect cl-cc/runtime::*rt-finalization-queue* :to-equal (list object-addr))
    ;; Running pending finalizers executes them and clears the queue
    (cl-cc/runtime::rt-run-pending-finalizers)
    (expect finalized :to-equal object-addr)))

(it-sequential "FR-300: Runtime handler and restart stacks establish dynamic recovery frames." (let ((handled nil))
    (multiple-value-bind (value foundp)
        (cl-cc/runtime::rt-establish-handler
         'error
         (lambda (condition) (setf handled condition) :handled)
         (lambda () (cl-cc/runtime::rt-dispatch-signal
                     (make-condition 'simple-error :format-control "x"))))
      (expect foundp :to-be-truthy)
      (expect value :to-be :handled)
      (expect (typep handled 'simple-error) :to-be-truthy)))
  (multiple-value-bind (value foundp)
      (cl-cc/runtime::rt-establish-restart
       'use-value
       (lambda (x) x)
       (lambda () (cl-cc/runtime::rt-dispatch-restart 'use-value '(42))))
    (expect foundp :to-be-truthy)
    (expect value :to-equal 42)))

;;; ------------------------------------------------------------
;;; FR-341: GC Pause Time Goals / SLO
;;; ------------------------------------------------------------

(it-sequential "FR-341: Max pause time parameter is configured and accessible." (expect (numberp cl-cc/runtime::*gc-max-pause-ms*) :to-be-truthy)
  (expect (>= cl-cc/runtime::*gc-max-pause-ms* 1) :to-be-truthy))

(it-sequential "FR-341: GC pause accounting increments exceeded-count when the SLO budget is exceeded." (let ((heap (%make-small-heap-fr))
        (cl-cc/runtime::*gc-max-pause-ms* 0))
    (let ((exceeded-before (cl-cc/runtime::rt-heap-pause-exceeded-count heap))
          (budget-before (cl-cc/runtime::rt-heap-incremental-work-budget heap)))
      (cl-cc/runtime::%rt-gc-note-pause
       heap
       (- (get-internal-real-time) internal-time-units-per-second))
      (expect (cl-cc/runtime::rt-heap-pause-exceeded-count heap) :to-equal (1+ exceeded-before))
      (expect (< (cl-cc/runtime::rt-heap-incremental-work-budget heap)
                      budget-before) :to-be-truthy))))

(it-sequential "FR-341: Throughput target parameter is configured in the valid ratio range." (expect (numberp cl-cc/runtime::*gc-throughput-target*) :to-be-truthy)
  (expect (>= cl-cc/runtime::*gc-throughput-target* 0.0d0) :to-be-truthy)
  (expect (<= cl-cc/runtime::*gc-throughput-target* 1.0d0) :to-be-truthy))

;;; ------------------------------------------------------------
;;; Integrated FR Tests
;;; ------------------------------------------------------------

(it-sequential "FR-331+333+336: Allocate objects, trigger minor GC, verify heap integrity." (let ((heap (%make-small-heap-fr)))
    (loop repeat 10
          for i from 1
          do (let ((addr (cl-cc/runtime::rt-gc-alloc heap cl-cc/runtime:+rt-tag-cons+ 3)))
               (%fr-write-object heap addr 3 cl-cc/runtime:+rt-tag-cons+)
               (cl-cc/runtime::rt-heap-set heap (+ addr 1)
                                          (cl-cc/runtime::encode-fixnum i))
               (cl-cc/runtime::rt-heap-set heap (+ addr 2)
                                          (cl-cc/runtime::encode-fixnum (+ i 100)))
               (expect (integerp addr) :to-be-truthy)
                (expect (>= addr 0) :to-be-truthy)))
    (cl-cc/runtime::rt-gc-minor-collect heap)
    (expect (cl-cc/runtime::rt-gc-verify-heap heap) :to-be-truthy)))

(it-sequential "FR-700: heap allocation profiler emits the documented plist report shape." (let ((cl-cc/runtime::*gc-profile-enabled* t)
        (cl-cc/runtime::*gc-profile-interval* 16)
        (cl-cc/runtime::*gc-profile-bytes-since-sample* 0)
        (cl-cc/runtime::*gc-profile-samples* (make-hash-table :test #'equal))
        (cl-cc/runtime::*gc-profile-current-function* 'test-allocation-site))
    (cl-cc/runtime::rt-gc-profile-sample 48)
    (let ((report (cl-cc/runtime::rt-gc-profile-report)))
      (expect (getf report :enabled-p) :to-be t)
      (expect (getf report :interval-bytes) :to-equal 16)
      (expect (listp (getf report :hot-spots)) :to-be-truthy)
      (let ((spot (first (getf report :hot-spots))))
        (expect (getf spot :function) :to-be 'test-allocation-site)
        (expect (getf spot :count) :to-equal 3)))))

;;; ------------------------------------------------------------
;;; FR-730..734: GC lifecycle references, finalizers, pinning
;;; ------------------------------------------------------------

(defun %gc-fr-marked-set (&rest addrs)
  (let ((marked (make-hash-table :test #'eql)))
    (dolist (addr addrs marked)
      (setf (gethash addr marked) t))))

(it-sequential "FR-730: Weak pointers do not keep an unreachable heap referent alive." (let* ((heap (%make-small-heap-fr))
         (addr (cl-cc/runtime::rt-gc-alloc heap cl-cc/runtime:+rt-tag-cons+ 3))
         (weak (cl-cc/runtime::rt-make-weak-pointer addr))
         (cl-cc/runtime::*rt-reference-registry* (list weak)))
    (%fr-write-object heap addr 3 cl-cc/runtime:+rt-tag-cons+)
    (cl-cc/runtime::%rt-gc-process-weak-references heap (%gc-fr-marked-set))
    (expect (cl-cc/runtime::rt-weak-pointer-value weak) :to-be-falsy)))

(it-sequential "FR-730: Weak pointer values survive when the strong graph marks their referent." (let* ((heap (%make-small-heap-fr))
         (addr (cl-cc/runtime::rt-gc-alloc heap cl-cc/runtime:+rt-tag-cons+ 3))
         (weak (cl-cc/runtime::rt-make-weak-pointer addr))
         (cl-cc/runtime::*rt-reference-registry* (list weak)))
    (%fr-write-object heap addr 3 cl-cc/runtime:+rt-tag-cons+)
    (cl-cc/runtime::%rt-gc-process-weak-references heap (%gc-fr-marked-set addr))
    (expect (cl-cc/runtime::rt-weak-pointer-value weak) :to-equal addr)))

(it-sequential "FR-731: Ephemeron processing conditionally marks the value when the key is live." (let* ((heap (%make-small-heap-fr))
         (key (cl-cc/runtime::rt-gc-alloc heap cl-cc/runtime:+rt-tag-cons+ 3))
         (value (cl-cc/runtime::rt-gc-alloc heap cl-cc/runtime:+rt-tag-cons+ 3))
         (marked (%gc-fr-marked-set key))
         (cl-cc/runtime::*rt-ephemeron-registry* nil))
    (%fr-write-object heap key 3 cl-cc/runtime:+rt-tag-cons+)
    (%fr-write-object heap value 3 cl-cc/runtime:+rt-tag-cons+)
    (cl-cc/runtime::rt-make-ephemeron key value)
    (cl-cc/runtime::%rt-gc-process-ephemerons heap marked)
    (expect (gethash value marked) :to-be-truthy)))

(it-sequential "FR-732: Unreachable finalized objects are queued and finalized explicitly after GC." (let* ((heap (%make-small-heap-fr))
         (addr (cl-cc/runtime::rt-gc-alloc heap cl-cc/runtime:+rt-tag-cons+ 3))
         (seen nil)
         (cl-cc/runtime::*rt-finalizer-registry* nil)
         (cl-cc/runtime::*pending-finalizers* nil)
         (cl-cc/runtime::*rt-finalization-queue* nil))
    (%fr-write-object heap addr 3 cl-cc/runtime:+rt-tag-cons+)
    (cl-cc/runtime::register-finalizer addr (lambda (obj) (push obj seen)))
    (cl-cc/runtime::%rt-gc-process-finalizers heap (%gc-fr-marked-set))
    (expect cl-cc/runtime::*rt-finalization-queue* :to-equal (list addr))
    (expect (cl-cc/runtime::rt-run-pending-finalizers) :to-equal 1)
    (expect seen :to-equal (list addr))))

(it-sequential "FR-733: Pinned objects are recorded for compaction and unpinned on exit." (let* ((heap (%make-small-heap-fr))
         (addr (cl-cc/runtime::rt-gc-alloc heap cl-cc/runtime:+rt-tag-cons+ 3)))
    (%fr-write-object heap addr 3 cl-cc/runtime:+rt-tag-cons+)
    (cl-cc/runtime::with-pinned-objects ((pinned heap addr))
      (expect pinned :to-equal addr)
      (expect (cl-cc/runtime::rt-object-pinned-p heap addr) :to-be-truthy))
    (expect (cl-cc/runtime::rt-object-pinned-p heap addr) :to-be-falsy)))

(it-sequential "FR-734: Runtime weak hash tables remove entries whose weak key is unreachable." (let* ((heap (%make-small-heap-fr))
         (key (cl-cc/runtime::rt-gc-alloc heap cl-cc/runtime:+rt-tag-cons+ 3))
         (value :payload)
         (ht (cl-cc/runtime::rt-make-hash-table :weakness :key))
         (cl-cc/runtime::*rt-weak-hash-table-registry* (list ht)))
    (%fr-write-object heap key 3 cl-cc/runtime:+rt-tag-cons+)
    (cl-cc/runtime::rt-sethash key ht value)
    (expect (cl-cc/runtime::rt-hash-count ht) :to-equal 1)
    (cl-cc/runtime::%rt-gc-process-weak-hash-tables heap (%gc-fr-marked-set))
    (expect (cl-cc/runtime::rt-hash-count ht) :to-equal 0)))

;;; ------------------------------------------------------------
;;; FR-373: Heap ASLR (⚠️ Pure CL interface)
;;; ------------------------------------------------------------

(it-sequential-each (("rt-heap-randomize-base"  cl-cc/runtime::rt-heap-randomize-base)
                      ("rt-install-stack-guard"  cl-cc/runtime::rt-install-stack-guard))
    "FR-373/FR-376: Pure CL GC interface entry point ~A is fbound."
    (label sym)
  (declare (ignore label))
  (expect (fboundp sym) :to-be-truthy))

(it-sequential "FR-373: rt-heap-randomize-base returns a non-negative integer offset." (let ((offset (cl-cc/runtime::rt-heap-randomize-base)))
    (expect (integerp offset) :to-be-truthy)
    (expect (>= offset 0) :to-be-truthy)))

;;; ------------------------------------------------------------
;;; FR-376: Guard Pages for Stack Overflow (⚠️ Pure CL interface)
;;; ------------------------------------------------------------

(it-sequential "FR-376: rt-install-stack-guard fails until native guard pages are wired." (signals error (cl-cc/runtime::rt-install-stack-guard 0 4096)))

(progn
  (it-sequential "Heap advice still fails until native heap addressing is available." (let ((heap (cl-cc/runtime::make-rt-heap :young-size 64 :old-size 64)))
      (signals error (cl-cc/runtime::rt-heap-madvise-sequential heap 0 8))
      (signals error (cl-cc/runtime::rt-heap-madvise-willneed heap 0 8))
      (signals error (cl-cc/runtime::rt-heap-madvise-hugepage heap))))

  (it-sequential "Anonymous mmap exposes native bytes, protection, advice, and release state." (let ((region (cl-cc/runtime::rt-allocate-anonymous-memory 4096)))
      (unwind-protect
           (progn
             (expect (plusp (cl-cc/runtime::rt-mmap-region-address region)) :to-be-truthy)
             (expect (cl-cc/runtime::rt-mmap-set region 0 37) :to-equal 37)
             (expect (cl-cc/runtime::rt-mmap-ref region 0) :to-equal 37)
             (expect (cl-cc/runtime::mmap-advice region :sequential) :to-be-truthy)
             (expect (cl-cc/runtime::rt-mprotect
               region 4096 cl-cc/runtime::+rt-prot-read+) :to-be-truthy)
             (signals error (cl-cc/runtime::rt-mmap-set region 0 99)))
        (unless (cl-cc/runtime::rt-mmap-region-released-p region)
          (cl-cc/runtime::rt-munmap region)))
      (signals error (cl-cc/runtime::rt-mmap-ref region 0))))

  (it-sequential "A shared mapping flushes compatibility-array writes through native msync." (let ((path (merge-pathnames
                 (format nil "cl-cc-runtime-mmap-~A.bin" (gensym))
                 (uiop:temporary-directory))))
      (unwind-protect
           (progn
             (with-open-file (out path :direction :output
                                       :if-exists :supersede
                                       :element-type (quote (unsigned-byte 8)))
               (write-sequence (make-array 4096
                                           :element-type (quote (unsigned-byte 8))
                                           :initial-element 0)
                               out))
             (cl-cc/runtime::with-mmap
                 (region path :protection :read-write :flags :shared)
               (setf (aref (cl-cc/runtime::mmap-array region) 0) 42)
               (expect (cl-cc/runtime::mmap-sync region) :to-be-truthy)
               (with-open-file (in path :direction :input
                                        :element-type (quote (unsigned-byte 8)))
                 (expect (read-byte in) :to-equal 42))))
        (when (probe-file path)
          (delete-file path))))))

(it-sequential "FR-623: huge-page mmap requires a native backend." (signals error (cl-cc/runtime::rt-huge-page-mmap nil 4096
                                     (logior cl-cc/runtime::+rt-prot-read+
                                             cl-cc/runtime::+rt-prot-write+)
                                     cl-cc/runtime::+rt-map-anonymous+
                                     nil 0))
  (expect (cl-cc/runtime::try-enable-huge-pages) :to-be-falsy)
  (expect (cl-cc/runtime::huge-pages-enabled-p) :to-be-falsy))

;; fr-772-xom-requires-native-support omitted: platform-dependent. It relies on
;; rt-xom-supported-p returning nil (no execute-only-memory support), which
;; holds on the CI Linux target but not on hosts where XOM is available; the
;; flet stub does not override the global called from rt-xom-effective-prot.

;;; ------------------------------------------------------------
;;; FR-377: Immortal / Permanent Objects (⚠️ Pure CL interface)
;;; ------------------------------------------------------------

(it-sequential "FR-377: rt-make-immortal and rt-immortal-p are fbound." (expect (fboundp 'cl-cc/runtime::rt-make-immortal) :to-be-truthy)
  (expect (fboundp 'cl-cc/runtime::rt-immortal-p) :to-be-truthy))

(it-sequential "FR-377: Creating an immortal object returns an immortal address." (let* ((handle (cl-cc/runtime::rt-make-immortal cl-cc/runtime:+rt-tag-cons+ 1)))
    (expect handle :to-be-truthy)
    (expect (cl-cc/runtime::rt-immortal-p handle) :to-be-truthy)
    (expect t :to-be-truthy)))

(it-sequential "FR-377: Creating immortal objects increments the count." (let ((before (hash-table-count cl-cc/runtime::*rt-immortal-registry*)))
    (cl-cc/runtime::rt-make-immortal cl-cc/runtime:+rt-tag-cons+ 1)
    (let ((after (hash-table-count cl-cc/runtime::*rt-immortal-registry*)))
      (expect (> after before) :to-be-truthy))))

;;; ------------------------------------------------------------
;;; FR-371: GC Safepoints (⚠️ Pure CL interface)
;;; ------------------------------------------------------------

(it-sequential "FR-371: GC safepoint interface is fbound (Pure CL cooperative safe-region API)." (expect (or (multiple-value-bind (symbol status)
                       (find-symbol "RT-GC-REQUEST-STOP" "CL-CC/RUNTIME")
                     (and status (fboundp symbol)))
                   (and (find-symbol "RT-GC-ENTER-SAFE-REGION" "CL-CC/RUNTIME")
                        (multiple-value-bind (symbol status)
                            (find-symbol "RT-GC-ENTER-SAFE-REGION" "CL-CC/RUNTIME")
                          (and status (fboundp symbol))))) :to-be-truthy))

;;; ------------------------------------------------------------
;;; FR-338: Parallel GC worker interface (⚠️ Pure CL/SB-THREAD interface)
;;; ------------------------------------------------------------

(it-sequential "FR-338: root-scan worker API returns registered root addresses in fallback mode." (let ((heap (%make-small-heap-fr)))
    (let* ((addr (cl-cc/runtime::rt-gc-alloc heap cl-cc/runtime:+rt-tag-cons+ 3))
           (root (cons nil addr)))
      (%fr-write-object heap addr 3 cl-cc/runtime:+rt-tag-cons+)
      (cl-cc/runtime::rt-gc-add-root heap root)
      (let ((roots (cl-cc/runtime::rt-gc-parallel-root-scan heap 1)))
        (expect (member addr roots :test #'eql) :to-be-truthy))
      (cl-cc/runtime::rt-gc-remove-root heap root))))

(it-sequential "FR-338: worker-count detection returns a portable non-negative integer." (expect (integerp (cl-cc/runtime::rt-gc-detect-worker-count)) :to-be-truthy)
  (expect (>= (cl-cc/runtime::rt-gc-detect-worker-count) 0) :to-be-truthy))

;;; ------------------------------------------------------------
;;; FR-343..345: TLAB and zero-fill interface (⚠️ Pure CL implementation)
;;; ------------------------------------------------------------

(it-sequential "FR-343: rt-gc-tlab-alloc allocates from a thread-local buffer and advances FREE." (let ((heap (%make-small-heap-fr))
        (cl-cc/runtime::*gc-tlab-size-words* 8)
        (cl-cc/runtime::*rt-thread-local-heaps* nil))
    (let* ((addr (cl-cc/runtime::rt-gc-tlab-alloc heap :worker-a 3))
           (tlab (cl-cc/runtime::%rt-gc-tlab-for heap :worker-a)))
      (expect (cl-cc/runtime::rt-tlab-base tlab) :to-equal addr)
      (expect (cl-cc/runtime::rt-tlab-free tlab) :to-equal (+ addr 3)))))

(it-sequential "FR-344: retiring TLABs records unused words and writes a dummy fill header." (let ((heap (%make-small-heap-fr))
        (cl-cc/runtime::*gc-tlab-size-words* 8)
        (cl-cc/runtime::*gc-tlab-retire-fill* t)
        (cl-cc/runtime::*rt-thread-local-heaps* nil))
    (let* ((addr (cl-cc/runtime::rt-gc-tlab-alloc heap :worker-b 3))
           (tlab (cl-cc/runtime::%rt-gc-tlab-for heap :worker-b))
           (free-before (cl-cc/runtime::rt-tlab-free tlab)))
      (declare (ignore addr))
      (cl-cc/runtime::rt-gc-tlab-retire-all heap)
      (expect (cl-cc/runtime::rt-tlab-retired-p tlab) :to-be-truthy)
      (expect (> (cl-cc/runtime::rt-tlab-waste-bytes tlab) 0) :to-be-truthy)
      (expect (cl-cc/runtime::rt-header-size
                   (cl-cc/runtime::rt-heap-object-header heap free-before)) :to-equal 5))))

(it-sequential "FR-345: Pure CL fallback exposes zero-initialized allocation words for SIMD zeroing sites." (let ((heap (%make-small-heap-fr))
        (cl-cc/runtime::*gc-tlab-size-words* 8)
        (cl-cc/runtime::*rt-thread-local-heaps* nil))
    (let ((addr (cl-cc/runtime::rt-gc-tlab-alloc heap :worker-c 3)))
      (expect (cl-cc/runtime::rt-heap-ref heap addr) :to-equal 0)
      (expect (cl-cc/runtime::rt-heap-ref heap (+ addr 1)) :to-equal 0)
      (expect (cl-cc/runtime::rt-heap-ref heap (+ addr 2)) :to-equal 0))))

(it-sequential "FR-345: rt-gc-simd-zero-fill is exported, callable, and returns its addr argument." (let ((heap (%make-small-heap-fr)))
    (expect (fboundp 'cl-cc/runtime::rt-gc-simd-zero-fill) :to-be-truthy)
    (let ((result (cl-cc/runtime::rt-gc-simd-zero-fill heap 64 4)))
      (expect result :to-equal 64))
    ;; Validate argument type checks reject negative inputs
    (signals error (cl-cc/runtime::rt-gc-simd-zero-fill heap -1 4))
    (signals error (cl-cc/runtime::rt-gc-simd-zero-fill heap 0 -1))))

;;; ------------------------------------------------------------
;;; FR-347: Compressed object references (⚠️ Pure CL offset codec)
;;; ------------------------------------------------------------

(it-sequential "FR-347: compressed object references round-trip as 32-bit heap-relative offsets." (let* ((heap (%make-small-heap-fr))
         (addr (cl-cc/runtime::rt-gc-alloc heap cl-cc/runtime:+rt-tag-cons+ 3))
         (offset (cl-cc/runtime::rt-compress-object-ref heap addr)))
    (expect (<= 0 offset #xffffffff) :to-be-truthy)
    (expect (cl-cc/runtime::rt-decompress-object-ref heap offset) :to-equal addr)))

;;; ------------------------------------------------------------
;;; FR-363..365: NUMA allocation, local GC schedule, and interleaving metadata
;;; ------------------------------------------------------------

(it-sequential "FR-363: portable NUMA local allocation records node metadata for the allocated address." (let ((heap (%make-small-heap-fr))
        (cl-cc/runtime::*rt-numa-enabled* t))
    (let ((addr (cl-cc/runtime::rt-numa-local-alloc heap :thread-1 3)))
      (expect (integerp addr) :to-be-truthy)
      (expect (gethash addr (cl-cc/runtime::rt-heap-numa-node-map heap)) :to-equal 0))))

(it-sequential "FR-364: NUMA-local GC API records a worker-to-node schedule." (let ((heap (%make-small-heap-fr))
        (cl-cc/runtime::*gc-worker-count* 2))
    (let ((schedule (cl-cc/runtime::rt-gc-numa-affinity heap 0)))
      (expect (length schedule) :to-equal 2)
      (expect (cl-cc/runtime::rt-heap-numa-gc-schedule heap) :to-equal schedule))))

(it-sequential "FR-365: interleaving API records shared-data region metadata." (let ((heap (%make-small-heap-fr)))
    (let ((region (cl-cc/runtime::rt-heap-interleave heap 4 8)))
      (expect (getf region :policy) :to-equal :interleave)
      (expect (member region (cl-cc/runtime::rt-heap-interleaved-regions heap)
                           :test #'equal) :to-be-truthy))))

;;; ------------------------------------------------------------
;;; FR-367 / FR-371 / FR-375 / FR-391 / FR-392 additional warning-FR evidence
;;; ------------------------------------------------------------

(it-sequential "FR-367: DTrace/eBPF portable probe stubs emit trace lines when enabled." (let ((cl-cc/runtime::*gc-probes-enabled* t))
    (let ((output (with-output-to-string (*trace-output*)
                    (cl-cc/runtime::rt-gc-probe-alloc 7)
                    (cl-cc/runtime::rt-gc-probe-gc-start :minor)
                    (cl-cc/runtime::rt-gc-probe-gc-end :minor))))
      (expect (search "GC-PROBE-ALLOC 7" output) :to-be-truthy)
      (expect (search "GC-PROBE-GC-START :MINOR" output) :to-be-truthy)
      (expect (search "GC-PROBE-GC-END :MINOR" output) :to-be-truthy))))

(it-sequential "FR-371: cooperative safepoint safe-region depth increments and decrements." (let ((thread-id :fr-371-thread))
    (expect (cl-cc/runtime::rt-gc-enter-safe-region thread-id) :to-equal 1)
    (expect (cl-cc/runtime::rt-gc-leave-safe-region thread-id) :to-equal 0)))

(it-sequential "FR-375: ASan shadow-memory fallback rejects poisoned heap addresses." (let ((heap (%make-small-heap-fr))
        (cl-cc/runtime::*rt-asan-enabled* t))
    (cl-cc/runtime::rt-sanitizer-reset-state)
    (cl-cc/runtime::rt-sanitizer-poison-address 0)
    (signals error (cl-cc/runtime::rt-heap-ref heap 0))
    (cl-cc/runtime::rt-sanitizer-unpoison-address 0)
    (expect (cl-cc/runtime::rt-heap-ref heap 0) :to-equal 0)))

(it-sequential "FR-391: high post-GC occupancy grows old-space capacity in Pure CL fallback." (let ((heap (cl-cc/runtime::make-rt-heap :young-size 64 :old-size 64)))
    (setf (cl-cc/runtime::rt-heap-young-free heap)
          (+ (cl-cc/runtime::rt-heap-young-from-base heap)
             (cl-cc/runtime::rt-heap-young-semi-size heap))
          (cl-cc/runtime::rt-heap-old-free heap)
          (+ (cl-cc/runtime::rt-heap-old-base heap)
             (cl-cc/runtime::rt-heap-old-size heap)))
    (let ((old-size-before (cl-cc/runtime::rt-heap-old-size heap)))
      (expect (cl-cc/runtime::rt-heap-maybe-grow heap) :to-be-truthy)
      (expect (> (cl-cc/runtime::rt-heap-old-size heap) old-size-before) :to-be-truthy))))

(it-sequential "FR-392: sustained low occupancy shrinks a previously grown Pure CL heap." (let ((heap (cl-cc/runtime::make-rt-heap :young-size 64 :old-size 64)))
    (setf (cl-cc/runtime::rt-heap-young-free heap)
          (+ (cl-cc/runtime::rt-heap-young-from-base heap)
             (cl-cc/runtime::rt-heap-young-semi-size heap))
          (cl-cc/runtime::rt-heap-old-free heap)
          (+ (cl-cc/runtime::rt-heap-old-base heap)
             (cl-cc/runtime::rt-heap-old-size heap)))
    (cl-cc/runtime::rt-heap-maybe-grow heap)
    (setf (cl-cc/runtime::rt-heap-young-free heap)
          (cl-cc/runtime::rt-heap-young-from-base heap)
          (cl-cc/runtime::rt-heap-old-free heap)
          (cl-cc/runtime::rt-heap-old-base heap))
    (let ((words-before (length (cl-cc/runtime::rt-heap-words heap))))
      (cl-cc/runtime::rt-heap-maybe-shrink heap)
      (cl-cc/runtime::rt-heap-maybe-shrink heap)
      (expect (cl-cc/runtime::rt-heap-maybe-shrink heap) :to-be-truthy)
      (expect (< (length (cl-cc/runtime::rt-heap-words heap)) words-before) :to-be-truthy))))
