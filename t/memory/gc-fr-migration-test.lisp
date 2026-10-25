;;;; tests/gc-fr-tests.lisp - GC Feature Requirement Evidence Tests
;;;;
;;;; Tests for FR implementations in the cl-cc/runtime generational GC:
;;;; - FR-331: Old-Space Free-List Reuse
;;;; - FR-333: Nursery Sizing Heuristics
;;;; - FR-335: Write Barrier Young-to-Young Elision
;;;; - FR-336: GC-NaN-Boxing Integration
;;;; - FR-341: GC Pause Time Goals / SLO

(in-package :cl-cc/runtime/memory/test)



;;; ------------------------------------------------------------
;;; Helpers
;;; ------------------------------------------------------------

(defun %make-small-heap-fr ()
  "Create a minimal heap: 64-word young space (32 per semi), 128-word old space."
  (cl-cc/runtime/memory:make-rt-heap :young-size 64 :old-size 128))

(defun %fr-write-object (heap addr size tag &optional (age 0))
  "Write a header at ADDR and return the address."
  (cl-cc/runtime/memory:rt-heap-set-header
   heap addr
   (cl-cc/runtime/memory:make-rt-header size tag :gc-bits age))
  addr)

(defun %fr-assert-free-list-blocks (heap expected-blocks)
  (let ((blocks (cl-cc/runtime/memory:rt-heap-free-list heap)))
    (expect (listp blocks) :to-be-truthy)
    (dolist (block expected-blocks)
      (expect (member block blocks :test #'equal) :to-be-truthy))))

(defun %fr-assert-pointer-tags (expected-tags)
  (dolist (case expected-tags)
    (destructuring-bind (addr tag) case
      (expect (= tag (cl-cc/runtime/values:pointer-tag
                 (cl-cc/runtime/values:encode-pointer addr tag))) :to-be-truthy))))

(defun %fr-assert-header-fields (header expected-size expected-tag expected-age)
  (expect (typep header '(unsigned-byte 64)) :to-be-truthy)
  (expect (= expected-size (cl-cc/runtime/memory:rt-header-size header)) :to-be-truthy)
  (expect (= expected-tag (cl-cc/runtime/memory:rt-header-type-tag header)) :to-be-truthy)
  (expect (= expected-age (cl-cc/runtime/memory:rt-header-age header)) :to-be-truthy))

;;; ------------------------------------------------------------
;;; FR-331: Old-Space Free-List Allocation Reuse
;;; ------------------------------------------------------------

(it-sequential "fr-331-free-list-exists"
  (let ((heap (%make-small-heap-fr)))
    (expect (listp (cl-cc/runtime/memory:rt-heap-free-list heap)) :to-be-truthy)
    (expect (null (cl-cc/runtime/memory:rt-heap-free-list heap)) :to-be-truthy)))

(it-sequential "fr-331-free-list-insert-find-and-split"
  (let* ((heap (%make-small-heap-fr))
         (addr (cl-cc/runtime/memory:rt-heap-old-base heap)))
    (%fr-write-object heap addr 8 cl-cc/runtime/values:+rt-tag-cons+)
    (setf (cl-cc/runtime/memory:rt-heap-old-free heap) (+ addr 8))
    (cl-cc/runtime/memory:rt-gc-major-collect heap)
    (let ((allocated (cl-cc/runtime/memory:rt-gc-alloc
                      heap :old 4)))
      (%fr-write-object heap allocated 4 cl-cc/runtime/values:+rt-tag-cons+)
      (expect (integerp allocated) :to-be-truthy)
      (expect (= addr allocated) :to-be-truthy)
      (expect (cl-cc/runtime/memory:rt-gc-verify-heap heap) :to-be-truthy)
      (%fr-assert-free-list-blocks heap (list (cons 4 (+ addr 4)))))))

(it-sequential "fr-331-free-list-blocks-enumeration"
  (let* ((heap (%make-small-heap-fr))
         (base (cl-cc/runtime/memory:rt-heap-old-base heap))
         (first-dead base)
         (rooted (+ base 8))
         (second-dead (+ base 16))
         (root (cons nil rooted)))
    (%fr-write-object heap first-dead 8 cl-cc/runtime/values:+rt-tag-cons+)
    (%fr-write-object heap rooted 8 cl-cc/runtime/values:+rt-tag-cons+)
    (%fr-write-object heap second-dead 16 cl-cc/runtime/values:+rt-tag-cons+)
    (setf (cl-cc/runtime/memory:rt-heap-old-free heap) (+ base 32))
    (cl-cc/runtime/memory:rt-gc-add-root heap root)
    (cl-cc/runtime/memory:rt-gc-major-collect heap)
    (%fr-assert-free-list-blocks heap (list (cons 8 first-dead)
                                            (cons 16 second-dead)))
    (cl-cc/runtime/memory:rt-gc-remove-root heap root)))

(it-sequential "fr-331-free-list-bin-index"
  (let ((class-24 (cl-cc/runtime/memory:rt-size-class-for 24))
        (class-32 (cl-cc/runtime/memory:rt-size-class-for 32))
        (class-256 (cl-cc/runtime/memory:rt-size-class-for 256))
        (class-512 (cl-cc/runtime/memory:rt-size-class-for 512)))
    (expect (= class-24 class-32) :to-be-truthy)
    (expect (>= class-256 class-32) :to-be-truthy)
    (expect (>= class-512 class-256) :to-be-truthy)))

(it-sequential "fr-156-size-class-segregated-allocator-evidence"
  (let ((small-class (cl-cc/runtime/memory:rt-size-class-for 16))
        (large-class (cl-cc/runtime/memory:rt-size-class-for 64)))
    (expect (= 16 small-class) :to-be-truthy)
    (expect (= 64 large-class) :to-be-truthy)))

;;; ------------------------------------------------------------
;;; FR-333: Nursery Sizing Heuristics
;;; ------------------------------------------------------------

(it-sequential "fr-333-explicit-young-size-configures-semispace"
  (let ((heap (cl-cc/runtime/memory:make-rt-heap
               :young-size 65536 :old-size 128)))
    (expect (= 32768 (cl-cc/runtime/memory:rt-heap-young-semi-size heap))
            :to-be-truthy)))

(it-sequential "fr-333-explicit-heap-dimensions-are-stable"
  (let ((first (cl-cc/runtime/memory:make-rt-heap
                :young-size 65536 :old-size 128))
        (second (cl-cc/runtime/memory:make-rt-heap
                 :young-size 65536 :old-size 128)))
    (expect (= (cl-cc/runtime/memory:rt-heap-young-semi-size first)
               (cl-cc/runtime/memory:rt-heap-young-semi-size second))
            :to-be-truthy)
    (expect (= 32768 (cl-cc/runtime/memory:rt-heap-young-semi-size first))
            :to-be-truthy)
    (expect (= (cl-cc/runtime/memory:rt-heap-old-size first)
               (cl-cc/runtime/memory:rt-heap-old-size second))
            :to-be-truthy)))

;;; ------------------------------------------------------------
;;; FR-335: Write Barrier Young-to-Young Elision
;;; ------------------------------------------------------------

(it-sequential "fr-335-write-barrier-young-to-young-fast-path"
  (let ((heap (%make-small-heap-fr)))
    (let ((obj-addr (cl-cc/runtime/memory:rt-gc-alloc heap cl-cc/runtime/values:+rt-tag-cons+ 3))
          (target   (cl-cc/runtime/memory:rt-gc-alloc heap cl-cc/runtime/values:+rt-tag-cons+ 3)))
      (%fr-write-object heap obj-addr 3 cl-cc/runtime/values:+rt-tag-cons+)
      (%fr-write-object heap target 3 cl-cc/runtime/values:+rt-tag-cons+)
      (setf (cl-cc/runtime/memory:rt-heap-gc-state heap) :major-gc)
      (cl-cc/runtime/memory:rt-gc-write-barrier heap obj-addr 1 target)
      (expect (= target (cl-cc/runtime/memory:rt-heap-ref heap (+ obj-addr 1))) :to-be-truthy)
      (expect (find-if-not #'zerop (cl-cc/runtime/memory:rt-heap-card-table heap)) :to-be-falsy)
      (expect (= 0 (length (cl-cc/runtime/memory:rt-heap-satb-queue heap))) :to-be-truthy))))

(it-sequential "fr-335-barrier-buffer-flush"
  (let ((heap (%make-small-heap-fr)))
    (let ((old-addr (cl-cc/runtime/memory:rt-heap-old-base heap)))
      (push old-addr (cl-cc/runtime/memory:rt-heap-barrier-buffer heap))
      (expect (cl-cc/runtime/memory:rt-card-dirty-p heap old-addr) :to-be-falsy)
      (cl-cc/runtime/memory:rt-gc-flush-barrier-buffer heap)
      (expect (cl-cc/runtime/memory:rt-card-dirty-p heap old-addr) :to-be-truthy)
      (expect (= 0 (length (cl-cc/runtime/memory:rt-heap-barrier-buffer heap))) :to-be-truthy))))

;;; ------------------------------------------------------------
;;; FR-336: GC-NaN-Boxing Integration
;;; ------------------------------------------------------------

(it-sequential "fr-336-val-pointer-p-detection"
  (expect (cl-cc/runtime/values:val-pointer-p
                 (cl-cc/runtime/values:encode-fixnum 42)) :to-be-falsy)
  (expect (cl-cc/runtime/values:val-pointer-p cl-cc/runtime/values:+val-t+) :to-be-falsy)
  (expect (cl-cc/runtime/values:val-pointer-p cl-cc/runtime/values:+val-nil+) :to-be-falsy))

(it-sequential "fr-336-decode-pointer-roundtrip"
  (let* ((addr #xABCD)
         (encoded (cl-cc/runtime/values:encode-pointer addr cl-cc/runtime/values:+tag-object+)))
    (expect (cl-cc/runtime/values:val-pointer-p encoded) :to-be-truthy)
    (expect (= addr (cl-cc/runtime/values:decode-pointer encoded)) :to-be-truthy)))

(it-sequential "fr-336-pointer-tag-extraction"
  (%fr-assert-pointer-tags
   `((#x100 ,cl-cc/runtime/values:+tag-object+)
     (#x200 ,cl-cc/runtime/values:+tag-cons+)
     (#x300 ,cl-cc/runtime/values:+tag-symbol+))))

(it-sequential "fr-336-val-cons-p-detection"
  (let ((cons-ptr (cl-cc/runtime/values:encode-pointer #x500 cl-cc/runtime/values:+tag-cons+))
        (obj-ptr (cl-cc/runtime/values:encode-pointer #x600 cl-cc/runtime/values:+tag-object+)))
    (expect (cl-cc/runtime/values:val-cons-p cons-ptr) :to-be-truthy)
    (expect (cl-cc/runtime/values:val-cons-p obj-ptr) :to-be-falsy)))

(it-sequential "fr-140-symbol-immediates-roundtrip-common-symbols"
  (expect (= cl-cc/runtime/values:+val-nil+
             (cl-cc/runtime/values:cl-value->val nil)) :to-be-truthy)
  (expect (= cl-cc/runtime/values:+val-t+
             (cl-cc/runtime/values:cl-value->val t)) :to-be-truthy)
  (let ((encoded (cl-cc/runtime/values:cl-value->val :key)))
    (expect (integerp encoded) :to-be-truthy)
    (expect (cl-cc/runtime/values:val-pointer-p encoded) :to-be-falsy)
    (expect (cl-cc/runtime/values:val->cl-value encoded) :to-be :key)))

(it-sequential "fr-264-compressed-pointer-roundtrip"
  (let ((cl-cc/runtime/values:*compressed-pointers-enabled* t)
        (cl-cc/runtime/values:*heap-base-address* #x10000000))
    (let ((encoded (cl-cc/runtime/values:encode-pointer #x10001000 cl-cc/runtime/values:+tag-object+)))
      (expect (cl-cc/runtime/values:val-compressed-pointer-p encoded) :to-be-truthy)
      (expect (= #x10001000 (cl-cc/runtime/values:decode-pointer encoded)) :to-be-truthy))))

(it-sequential "fr-265-small-string-optimization-roundtrip"
  (let ((encoded (cl-cc/runtime/values:cl-value->val "abc")))
    (expect (cl-cc/runtime/values:val-sso-string-p encoded) :to-be-truthy)
    (expect (cl-cc/runtime/values:val->cl-value encoded) :to-equal "abc")))

(it-sequential "fr-266-compressed-object-header-is-one-word"
  (let ((header (cl-cc/runtime/memory:make-rt-header 42 cl-cc/runtime/values:+rt-tag-cons+ :gc-bits 2)))
    (%fr-assert-header-fields header 42 cl-cc/runtime/values:+rt-tag-cons+ 2)))

(it-sequential "fr-184-weak-reference-and-finalizer-evidence"
  (let* ((heap (%make-small-heap-fr))
         (object-addr (cl-cc/runtime/memory:rt-gc-alloc heap :old 3))
         (weak (cl-cc/runtime/memory:rt-make-weak-ref object-addr))
         (finalized nil)
         (cl-cc/runtime/memory:*rt-reference-registry* nil)
         (cl-cc/runtime/memory:*rt-finalizer-registry* nil)
         (cl-cc/runtime/memory:*rt-finalization-queue* nil))
    (%fr-write-object heap object-addr 3 cl-cc/runtime/values:+rt-tag-cons+)
    (cl-cc/runtime/memory:register-finalizer
     object-addr (lambda (object) (setf finalized object)))
    (cl-cc/runtime/memory:rt-gc-major-collect heap)
    (expect (cl-cc/runtime/memory:rt-ref-get weak) :to-be-null)
    (expect cl-cc/runtime/memory:*rt-finalization-queue*
            :to-equal (list object-addr))
    (cl-cc/runtime/memory:rt-run-pending-finalizers)
    (expect (= object-addr finalized) :to-be-truthy)))

(it-sequential "fr-300-runtime-condition-restart-stacks"
  (let ((handled nil))
    (multiple-value-bind (value foundp)
        (cl-cc/runtime/conditions:rt-establish-handler
         'error
         (lambda (condition) (setf handled condition) :handled)
         (lambda () (cl-cc/runtime/conditions:rt-dispatch-signal
                     (make-condition 'simple-error :format-control "x"))))
      (expect foundp :to-be-truthy)
      (expect value :to-be :handled)
      (expect (typep handled 'simple-error) :to-be-truthy)))
  (multiple-value-bind (value foundp)
      (cl-cc/runtime/conditions:rt-establish-restart
       'use-value
       (lambda (x) x)
       (lambda () (cl-cc/runtime/conditions:rt-dispatch-restart 'use-value '(42))))
    (expect foundp :to-be-truthy)
    (expect (= 42 value) :to-be-truthy)))

;;; ------------------------------------------------------------
;;; FR-341: GC Pause Time Goals / SLO
;;; ------------------------------------------------------------

(it-sequential "fr-341-pause-target-configured"
  (expect (numberp cl-cc/runtime/memory:*gc-pause-target-ms*) :to-be-truthy)
  (expect (>= cl-cc/runtime/memory:*gc-pause-target-ms* 1) :to-be-truthy))

(it-sequential "fr-341-public-pause-accounting-records-major-collection"
  (let ((heap (%make-small-heap-fr)))
    (cl-cc/runtime/memory:rt-gc-major-collect heap)
    (expect (numberp (cl-cc/runtime/memory:rt-heap-gc-pause-total heap))
            :to-be-truthy)
    (expect (>= (cl-cc/runtime/memory:rt-heap-gc-pause-max heap) 0)
            :to-be-truthy)))

(it-sequential "fr-341-public-gc-pacer-settings"
  (expect (numberp cl-cc/runtime/memory:*gc-allocation-rate-limit-words-per-sec*)
          :to-be-truthy)
  (expect (>= cl-cc/runtime/memory:*gc-allocation-rate-limit-words-per-sec* 0)
          :to-be-truthy)
  (expect (numberp cl-cc/runtime/memory:*gc-pause-target-ms*) :to-be-truthy))

;;; ------------------------------------------------------------
;;; Integrated FR Tests
;;; ------------------------------------------------------------

(it-sequential "fr-integrated-alloc-and-gc"
  (let ((heap (%make-small-heap-fr)))
    (loop repeat 10
          for i from 1
          do (let ((addr (cl-cc/runtime/memory:rt-gc-alloc heap cl-cc/runtime/values:+rt-tag-cons+ 3)))
               (%fr-write-object heap addr 3 cl-cc/runtime/values:+rt-tag-cons+)
               (cl-cc/runtime/memory:rt-heap-set heap (+ addr 1)
                                          (cl-cc/runtime/values:encode-fixnum i))
               (cl-cc/runtime/memory:rt-heap-set heap (+ addr 2)
                                          (cl-cc/runtime/values:encode-fixnum (+ i 100)))
               (expect (integerp addr) :to-be-truthy)
                (expect (>= addr 0) :to-be-truthy)))
    (cl-cc/runtime/memory:rt-gc-minor-collect heap)
    (expect (cl-cc/runtime/memory:rt-gc-verify-heap heap) :to-be-truthy)))

(it-sequential "fr-700-heap-profiler-report-has-stable-output-format"
  (let ((cl-cc/runtime/memory:*gc-profile-enabled* t)
        (cl-cc/runtime/memory:*gc-profile-interval* 16))
    (cl-cc/runtime/memory:rt-gc-profile-sample 48)
    (let* ((report (cl-cc/runtime/memory:rt-gc-profile-report))
           (hot-spots (getf report :hot-spots))
           (spot (first hot-spots)))
      (expect (getf report :enabled-p) :to-be t)
      (expect (= 16 (getf report :interval-bytes)) :to-be-truthy)
      (expect (listp hot-spots) :to-be-truthy)
      (expect (member :function spot) :to-be-truthy)
      (expect (>= (getf spot :count) 3) :to-be-truthy))))

;;; ------------------------------------------------------------
;;; FR-730..734: GC lifecycle references, finalizers, pinning
;;; ------------------------------------------------------------

(defun %gc-fr-marked-set (&rest addrs)
  (let ((marked (make-hash-table :test #'eql)))
    (dolist (addr addrs marked)
      (setf (gethash addr marked) t))))

(it-sequential "fr-730-weak-pointer-clears-unmarked-heap-referent"
  (let* ((heap (%make-small-heap-fr))
         (addr (cl-cc/runtime/memory:rt-gc-alloc heap :old 3))
         (weak (cl-cc/runtime/memory:rt-make-weak-pointer addr))
         (cl-cc/runtime/memory:*rt-reference-registry* nil))
    (%fr-write-object heap addr 3 cl-cc/runtime/values:+rt-tag-cons+)
    (cl-cc/runtime/memory:rt-gc-major-collect heap)
    (expect (cl-cc/runtime/memory:rt-weak-pointer-value weak) :to-be-falsy)))

(it-sequential "fr-730-weak-pointer-keeps-marked-referent"
  (let* ((heap (%make-small-heap-fr))
         (addr (cl-cc/runtime/memory:rt-gc-alloc heap :old 3))
         (weak (cl-cc/runtime/memory:rt-make-weak-pointer addr))
         (root (cons nil addr))
         (cl-cc/runtime/memory:*rt-reference-registry* nil))
    (%fr-write-object heap addr 3 cl-cc/runtime/values:+rt-tag-cons+)
    (cl-cc/runtime/memory:rt-gc-add-root heap root)
    (cl-cc/runtime/memory:rt-gc-major-collect heap)
    (expect (= addr (cl-cc/runtime/memory:rt-weak-pointer-value weak))
            :to-be-truthy)
    (cl-cc/runtime/memory:rt-gc-remove-root heap root)))

(it-sequential "fr-731-ephemeron-marks-value-when-key-is-live"
  (let* ((heap (%make-small-heap-fr))
         (key (cl-cc/runtime/memory:rt-gc-alloc heap :old 3))
         (value (cl-cc/runtime/memory:rt-gc-alloc heap :old 3))
         (weak-value (cl-cc/runtime/memory:rt-make-weak-pointer value))
         (root (cons nil key))
         (cl-cc/runtime/memory:*rt-reference-registry* nil)
         (cl-cc/runtime/memory:*rt-ephemeron-registry* nil))
    (%fr-write-object heap key 3 cl-cc/runtime/values:+rt-tag-cons+)
    (%fr-write-object heap value 3 cl-cc/runtime/values:+rt-tag-cons+)
    (cl-cc/runtime/memory:rt-make-ephemeron key value)
    (cl-cc/runtime/memory:rt-gc-add-root heap root)
    (cl-cc/runtime/memory:rt-gc-major-collect heap)
    (expect (= value (cl-cc/runtime/memory:rt-weak-pointer-value weak-value))
            :to-be-truthy)
    (cl-cc/runtime/memory:rt-gc-remove-root heap root)))

(it-sequential "fr-732-finalizer-is-scheduled-after-gc-and-runs-outside-gc-pause"
  (let* ((heap (%make-small-heap-fr))
         (addr (cl-cc/runtime/memory:rt-gc-alloc heap :old 3))
         (seen nil)
         (cl-cc/runtime/memory:*rt-finalizer-registry* nil)
         (cl-cc/runtime/memory:*pending-finalizers* nil)
         (cl-cc/runtime/memory:*rt-finalization-queue* nil))
    (%fr-write-object heap addr 3 cl-cc/runtime/values:+rt-tag-cons+)
    (cl-cc/runtime/memory:register-finalizer addr (lambda (object) (push object seen)))
    (cl-cc/runtime/memory:rt-gc-major-collect heap)
    (expect cl-cc/runtime/memory:*rt-finalization-queue* :to-equal (list addr))
    (expect (= 1 (cl-cc/runtime/memory:rt-run-pending-finalizers)) :to-be-truthy)
    (expect seen :to-equal (list addr))))

(it-sequential "fr-733-pinning-registers-and-cleans-up-relocation-barriers"
  (let* ((heap (%make-small-heap-fr))
         (addr (cl-cc/runtime/memory:rt-gc-alloc heap cl-cc/runtime/values:+rt-tag-cons+ 3)))
    (%fr-write-object heap addr 3 cl-cc/runtime/values:+rt-tag-cons+)
    (cl-cc/runtime/memory:with-pinned-objects ((pinned heap addr))
      (expect (= addr pinned) :to-be-truthy)
      (expect (cl-cc/runtime/memory:rt-object-pinned-p heap addr) :to-be-truthy))
    (expect (cl-cc/runtime/memory:rt-object-pinned-p heap addr) :to-be-falsy)))

(it-sequential "fr-734-weak-hash-table-removes-dead-weak-keys"
  (let* ((heap (%make-small-heap-fr))
         (key (cl-cc/runtime/memory:rt-gc-alloc heap :old 3))
         (value :payload)
         (ht (cl-cc/runtime/values:rt-make-hash-table :weakness :key))
         (cl-cc/runtime/values:*rt-weak-hash-table-registry* nil))
    (%fr-write-object heap key 3 cl-cc/runtime/values:+rt-tag-cons+)
    (cl-cc/runtime/values:rt-sethash key ht value)
    (expect (= 1 (cl-cc/runtime/values:rt-hash-count ht)) :to-be-truthy)
    (cl-cc/runtime/memory:rt-gc-major-collect heap)
    (expect (= 0 (cl-cc/runtime/values:rt-hash-count ht)) :to-be-truthy)))

;;; ------------------------------------------------------------
;;; FR-373: Heap ASLR (⚠️ Pure CL interface)
;;; ------------------------------------------------------------

(it-sequential "fr-gc-interface-function-exists rt-heap-randomize-base"
  (destructuring-bind (sym) (list 'cl-cc/runtime/memory:rt-heap-randomize-base)
    (expect (fboundp sym) :to-be-truthy)))

(it-sequential "fr-gc-interface-function-exists rt-install-stack-guard"
  (destructuring-bind (sym) (list 'cl-cc/runtime/memory:rt-install-stack-guard)
    (expect (fboundp sym) :to-be-truthy)))

(it-sequential "fr-373-heap-randomize-returns-value"
  (let ((offset (cl-cc/runtime/memory:rt-heap-randomize-base)))
    (expect (integerp offset) :to-be-truthy)
    (expect (>= offset 0) :to-be-truthy)))

;;; ------------------------------------------------------------
;;; FR-376: Guard Pages for Stack Overflow (⚠️ Pure CL interface)
;;; ------------------------------------------------------------

(it-sequential "fr-376-stack-guard-requires-native-backend"
  (signals error (cl-cc/runtime/memory:rt-install-stack-guard 0 4096)))

(it-sequential "fr-376-public-mmap-advice-requires-native-backend"
  (let ((region (cl-cc/runtime/memory:make-rt-mmap-region
                 :address 0 :length 8)))
    (signals error (cl-cc/runtime/memory:mmap-advice region :sequential))
    (signals error (cl-cc/runtime/memory:mmap-advice region :will-need))
    (signals error (cl-cc/runtime/memory:mmap-advice region :dont-need)))
  (signals error (cl-cc/runtime/memory:mmap-advice nil :sequential)))

(it-sequential "fr-623-huge-pages-require-native-backend"
  (signals error (cl-cc/runtime/memory:rt-huge-page-mmap nil 4096
                                     (logior cl-cc/runtime/memory:+rt-prot-read+
                                             cl-cc/runtime/memory:+rt-prot-write+)
                                     cl-cc/runtime/memory:+rt-map-anonymous+
                                     nil 0))
  (expect (cl-cc/runtime/memory:try-enable-huge-pages) :to-be-falsy)
  (expect (cl-cc/runtime/memory:huge-pages-enabled-p) :to-be-falsy))
(it-sequential "fr-772-executable-protection-excludes-write"
  (let ((xom-protection (logior cl-cc/runtime/memory:+rt-prot-read+
                                cl-cc/runtime/memory:+rt-prot-exec+)))
    (expect (logtest cl-cc/runtime/memory:+rt-prot-exec+ xom-protection)
            :to-be-truthy)
    (expect (not (logtest cl-cc/runtime/memory:+rt-prot-write+ xom-protection))
            :to-be-truthy)))

;;; ------------------------------------------------------------
;;; FR-377: Immortal / Permanent Objects (⚠️ Pure CL interface)
;;; ------------------------------------------------------------

(it-sequential "fr-377-immortal-functions-exist"
  (expect (fboundp 'cl-cc/runtime/memory:rt-make-immortal) :to-be-truthy)
  (expect (fboundp 'cl-cc/runtime/memory:rt-immortal-p) :to-be-truthy))

(it-sequential "fr-377-make-immortal-roundtrip"
  (let* ((handle (cl-cc/runtime/memory:rt-make-immortal cl-cc/runtime/values:+rt-tag-cons+ 1)))
    (expect handle :to-be-truthy)
    (expect (cl-cc/runtime/memory:rt-immortal-p handle) :to-be-truthy)
    (expect t :to-be-truthy)))

(it-sequential "fr-377-immortal-count-increases"
  (let ((before (cl-cc/runtime/memory:rt-immortal-objects-count)))
    (cl-cc/runtime/memory:rt-make-immortal cl-cc/runtime/values:+rt-tag-cons+ 1)
    (expect (> (cl-cc/runtime/memory:rt-immortal-objects-count) before)
            :to-be-truthy)))

;;; ------------------------------------------------------------
;;; FR-371: GC Safepoints (⚠️ Pure CL interface)
;;; ------------------------------------------------------------

(it-sequential "fr-371-gc-safepoint-interface-exists"
  (expect (or (fboundp 'cl-cc/runtime/memory:rt-gc-request)
              (fboundp 'cl-cc/runtime/memory:rt-gc-enter-safe-region))
          :to-be-truthy))

;;; ------------------------------------------------------------
;;; FR-338: Parallel GC worker interface (⚠️ Pure CL/SB-THREAD interface)
;;; ------------------------------------------------------------

(it-sequential "fr-338-parallel-root-scan-sequential-fallback"
  (let ((heap (%make-small-heap-fr)))
    (let* ((addr (cl-cc/runtime/memory:rt-gc-alloc heap cl-cc/runtime/values:+rt-tag-cons+ 3))
           (root (cons nil addr)))
      (%fr-write-object heap addr 3 cl-cc/runtime/values:+rt-tag-cons+)
      (cl-cc/runtime/memory:rt-gc-add-root heap root)
      (let ((roots (cl-cc/runtime/memory:rt-gc-parallel-root-scan heap 1)))
        (expect (member addr roots :test #'eql) :to-be-truthy))
      (cl-cc/runtime/memory:rt-gc-remove-root heap root))))

(it-sequential "fr-338-worker-count-detection-is-non-negative"
  (expect (integerp (cl-cc/runtime/memory:rt-gc-detect-worker-count)) :to-be-truthy)
  (expect (>= (cl-cc/runtime/memory:rt-gc-detect-worker-count) 0) :to-be-truthy))

;;; ------------------------------------------------------------
;;; FR-343..345: TLAB and zero-fill interface (⚠️ Pure CL implementation)
;;; ------------------------------------------------------------

(it-sequential "fr-343-tlab-alloc-bumps-private-buffer"
  (let ((heap (%make-small-heap-fr)))
    (let* ((first (cl-cc/runtime/memory:rt-gc-tlab-alloc heap :worker-a 3))
           (second (cl-cc/runtime/memory:rt-gc-tlab-alloc heap :worker-a 3)))
      (expect (integerp first) :to-be-truthy)
      (expect (= (+ first 3) second) :to-be-truthy))))

(it-sequential "fr-344-tlab-retire-records-waste-and-dummy-header"
  (let ((heap (%make-small-heap-fr)))
    (let ((addr (cl-cc/runtime/memory:rt-gc-tlab-alloc heap :worker-b 3)))
      (cl-cc/runtime/memory:rt-gc-tlab-retire-all heap)
      (let ((header (cl-cc/runtime/memory:rt-heap-object-header heap (+ addr 3))))
        (expect (integerp header) :to-be-truthy)
        (expect (plusp (cl-cc/runtime/memory:rt-header-size header))
                :to-be-truthy)
        (expect (cl-cc/runtime/memory:rt-gc-verify-heap heap) :to-be-truthy)))))

(it-sequential "fr-345-tlab-allocation-returns-zero-filled-words"
  (let ((heap (%make-small-heap-fr)))
    (let ((addr (cl-cc/runtime/memory:rt-gc-tlab-alloc heap :worker-c 3)))
      (expect (= 0 (cl-cc/runtime/memory:rt-heap-ref heap addr)) :to-be-truthy)
      (expect (= 0 (cl-cc/runtime/memory:rt-heap-ref heap (+ addr 1)))
              :to-be-truthy)
      (expect (= 0 (cl-cc/runtime/memory:rt-heap-ref heap (+ addr 2)))
              :to-be-truthy))))

(it-sequential "fr-345-simd-zero-fill-returns-addr-and-is-fboundp"
  (let ((heap (%make-small-heap-fr)))
    (expect (fboundp 'cl-cc/runtime/memory:rt-gc-simd-zero-fill) :to-be-truthy)
    (let ((result (cl-cc/runtime/memory:rt-gc-simd-zero-fill heap 64 4)))
      (expect (= 64 result) :to-be-truthy))
    ;; Validate argument type checks reject negative inputs
    (signals error (cl-cc/runtime/memory:rt-gc-simd-zero-fill heap -1 4))
    (signals error (cl-cc/runtime/memory:rt-gc-simd-zero-fill heap 0 -1))))

;;; ------------------------------------------------------------
;;; FR-347: Compressed object references (⚠️ Pure CL offset codec)
;;; ------------------------------------------------------------

(it-sequential "fr-347-compressed-reference-roundtrip"
  (let* ((heap (%make-small-heap-fr))
         (addr (cl-cc/runtime/memory:rt-gc-alloc heap cl-cc/runtime/values:+rt-tag-cons+ 3))
         (offset (cl-cc/runtime/memory:rt-compress-object-ref heap addr)))
    (expect (<= 0 offset #xffffffff) :to-be-truthy)
    (expect (= addr (cl-cc/runtime/memory:rt-decompress-object-ref heap offset)) :to-be-truthy)))

;;; ------------------------------------------------------------
;;; FR-363..365: NUMA allocation, local GC schedule, and interleaving metadata
;;; ------------------------------------------------------------

(it-sequential "fr-363-numa-local-alloc-records-node-metadata"
  (let ((heap (%make-small-heap-fr))
        (cl-cc/runtime/memory:*rt-numa-enabled* t))
    (let ((addr (cl-cc/runtime/memory:rt-numa-local-alloc heap :thread-1 3)))
      (expect (integerp addr) :to-be-truthy)
      (expect (= 0 (cl-cc/runtime/memory:rt-numa-node-of-thread :thread-1))
              :to-be-truthy))))

(it-sequential "fr-364-numa-gc-affinity-records-worker-schedule"
  (let ((heap (%make-small-heap-fr))
        (cl-cc/runtime/memory:*gc-worker-count* 2))
    (let ((schedule (cl-cc/runtime/memory:rt-gc-numa-affinity heap 0)))
      (expect (= 2 (length schedule)) :to-be-truthy)
      (expect (every (lambda (entry)
                       (and (integerp (getf entry :worker))
                            (= (getf entry :node)
                               (mod (getf entry :worker) 2))))
                     schedule)
              :to-be-truthy))))

(it-sequential "fr-365-heap-interleave-records-shared-region"
  (let ((heap (%make-small-heap-fr)))
    (let ((region (cl-cc/runtime/memory:rt-heap-interleave heap 4 8)))
      (expect (getf region :policy) :to-equal :interleave)
      (expect (= 8 (- (getf region :end) (getf region :start)))
              :to-be-truthy))))

;;; ------------------------------------------------------------
;;; FR-367 / FR-371 / FR-375 / FR-391 / FR-392 additional warning-FR evidence
;;; ------------------------------------------------------------

(it-sequential "fr-367-gc-probes-log-when-enabled"
  (let ((cl-cc/runtime/memory:*gc-probes-enabled* t))
    (let ((output (with-output-to-string (*trace-output*)
                    (cl-cc/runtime/memory:rt-gc-probe-alloc 7)
                    (cl-cc/runtime/memory:rt-gc-probe-gc-start :minor)
                    (cl-cc/runtime/memory:rt-gc-probe-gc-end :minor))))
      (expect (search "GC-PROBE-ALLOC 7" output) :to-be-truthy)
      (expect (search "GC-PROBE-GC-START :MINOR" output) :to-be-truthy)
      (expect (search "GC-PROBE-GC-END :MINOR" output) :to-be-truthy))))

(it-sequential "fr-371-safe-region-depth-roundtrip"
  (let ((thread-id :fr-371-thread))
    (expect (= 1 (cl-cc/runtime/memory:rt-gc-enter-safe-region thread-id)) :to-be-truthy)
    (expect (= 0 (cl-cc/runtime/memory:rt-gc-leave-safe-region thread-id)) :to-be-truthy)))

(it-sequential "fr-375-asan-shadow-memory-poisoning"
  (let ((heap (%make-small-heap-fr))
        (cl-cc/runtime/memory:*rt-asan-enabled* t))
    (cl-cc/runtime/memory:rt-sanitizer-reset-state)
    (cl-cc/runtime/memory:rt-sanitizer-poison-address 0)
    (signals error (cl-cc/runtime/memory:rt-heap-ref heap 0))
    (cl-cc/runtime/memory:rt-sanitizer-unpoison-address 0)
    (expect (= 0 (cl-cc/runtime/memory:rt-heap-ref heap 0)) :to-be-truthy)))

(it-sequential "fr-391-heap-growth-policy-expands-old-space"
  (let ((heap (cl-cc/runtime/memory:make-rt-heap :young-size 64 :old-size 64)))
    (setf (cl-cc/runtime/memory:rt-heap-young-free heap)
          (+ (cl-cc/runtime/memory:rt-heap-young-from-base heap)
             (cl-cc/runtime/memory:rt-heap-young-semi-size heap))
          (cl-cc/runtime/memory:rt-heap-old-free heap)
          (+ (cl-cc/runtime/memory:rt-heap-old-base heap)
             (cl-cc/runtime/memory:rt-heap-old-size heap)))
    (let ((old-size-before (cl-cc/runtime/memory:rt-heap-old-size heap)))
      (expect (cl-cc/runtime/memory:rt-heap-maybe-grow heap) :to-be-truthy)
      (expect (> (cl-cc/runtime/memory:rt-heap-old-size heap) old-size-before) :to-be-truthy))))

(it-sequential "fr-392-heap-shrink-policy-reduces-grown-heap"
  (let ((heap (cl-cc/runtime/memory:make-rt-heap :young-size 64 :old-size 64)))
    (setf (cl-cc/runtime/memory:rt-heap-young-free heap)
          (+ (cl-cc/runtime/memory:rt-heap-young-from-base heap)
             (cl-cc/runtime/memory:rt-heap-young-semi-size heap))
          (cl-cc/runtime/memory:rt-heap-old-free heap)
          (+ (cl-cc/runtime/memory:rt-heap-old-base heap)
             (cl-cc/runtime/memory:rt-heap-old-size heap)))
    (cl-cc/runtime/memory:rt-heap-maybe-grow heap)
    (setf (cl-cc/runtime/memory:rt-heap-young-free heap)
          (cl-cc/runtime/memory:rt-heap-young-from-base heap)
          (cl-cc/runtime/memory:rt-heap-old-free heap)
          (cl-cc/runtime/memory:rt-heap-old-base heap))
    (let ((words-before (length (cl-cc/runtime/memory:rt-heap-words heap))))
      (cl-cc/runtime/memory:rt-heap-maybe-shrink heap)
      (cl-cc/runtime/memory:rt-heap-maybe-shrink heap)
      (expect (cl-cc/runtime/memory:rt-heap-maybe-shrink heap) :to-be-truthy)
      (expect (< (length (cl-cc/runtime/memory:rt-heap-words heap)) words-before) :to-be-truthy))))
