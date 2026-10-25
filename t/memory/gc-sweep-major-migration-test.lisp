;;;; tests/gc-sweep-major-migration-test.lisp - GC Sweep and Major Collection Tests
;;;
;;; Tests for public major collection and sweep behavior:
;;; - Sweep reclaims dead (unmarked) old-space objects to the free-list
;;; - Sweep clears mark bits on live objects
;;; - Major GC increments counter and restores gc-state
;;; - Major GC reclaims unreachable old-space objects
;;; - Major GC preserves rooted old-space objects

(in-package :cl-cc/runtime/memory/test)


;;; ------------------------------------------------------------
;;; Test 9: public major collection and sweep behavior
;;; ------------------------------------------------------------

(it-sequential "gc-sweep-old-space-reclaims-dead-objects"
  (let ((cl-cc/runtime/memory:*gc-compaction-enabled* nil))
    (let* ((heap (cl-cc/runtime/memory:make-rt-heap :young-size 64 :old-size 64))
           (old-base (cl-cc/runtime/memory:rt-heap-old-base heap))
           (live-addr old-base)
           (dead-addr (+ old-base 3))
           (live-root (cons nil live-addr)))
      (cl-cc/runtime/memory:rt-heap-set-header
       heap live-addr
       (cl-cc/runtime/memory:make-rt-header 3 1 :gc-bits 0))
      (cl-cc/runtime/memory:rt-heap-set-header
       heap dead-addr
       (cl-cc/runtime/memory:make-rt-header 3 1 :gc-bits 0))
      (setf (cl-cc/runtime/memory:rt-heap-old-free heap) (+ old-base 6))
      (cl-cc/runtime/memory:rt-gc-add-root heap live-root)
      (cl-cc/runtime/memory:rt-gc-major-collect heap)
      (let ((stats (cl-cc/runtime/memory:rt-gc-stats heap)))
        (expect (>= (getf stats :words-collected) 3) :to-be-truthy)
        (expect (> (getf stats :free-list-count) 0) :to-be-truthy))
      (expect (cl-cc/runtime/memory:rt-gc-verify-heap heap) :to-be-truthy)
      (cl-cc/runtime/memory:rt-gc-remove-root heap live-root))))

(it-sequential "gc-sweep-old-space-all-live-no-reclaim"
  (let ((cl-cc/runtime/memory:*gc-compaction-enabled* nil))
    (let* ((heap (cl-cc/runtime/memory:make-rt-heap :young-size 64 :old-size 64))
           (old-base (cl-cc/runtime/memory:rt-heap-old-base heap))
           (root-a (cons nil old-base))
           (root-b (cons nil (+ old-base 3)))
           (roots (list root-a root-b)))
      (cl-cc/runtime/memory:rt-heap-set-header
       heap old-base
       (cl-cc/runtime/memory:make-rt-header 3 1 :gc-bits 0))
      (cl-cc/runtime/memory:rt-heap-set-header
       heap (+ old-base 3)
       (cl-cc/runtime/memory:make-rt-header 3 1 :gc-bits 0))
      (setf (cl-cc/runtime/memory:rt-heap-old-free heap) (+ old-base 6))
      (dolist (root roots)
        (cl-cc/runtime/memory:rt-gc-add-root heap root))
      (cl-cc/runtime/memory:rt-gc-major-collect heap)
      (let ((stats (cl-cc/runtime/memory:rt-gc-stats heap)))
        (expect (= 0 (getf stats :words-collected)) :to-be-truthy)
        (expect (= 0 (getf stats :free-list-count)) :to-be-truthy))
      (dolist (root roots)
        (cl-cc/runtime/memory:rt-gc-remove-root heap root)))))

;;; ------------------------------------------------------------
;;; Test 10: rt-gc-major-collect
;;; ------------------------------------------------------------

(it-sequential "gc-major-collect-increments-counter"
  (let ((heap (cl-cc/runtime/memory:make-rt-heap :young-size 64 :old-size 64)))
    (expect (= 0 (cl-cc/runtime/memory:rt-heap-major-gc-count heap)) :to-be-truthy)
    (cl-cc/runtime/memory:rt-gc-major-collect heap)
    (expect (= 1 (cl-cc/runtime/memory:rt-heap-major-gc-count heap)) :to-be-truthy)
    (expect (cl-cc/runtime/memory:rt-heap-gc-state heap) :to-be :normal)))

(it-sequential "gc-major-collect-gc-state-restored-on-empty-heap"
  (let ((heap (cl-cc/runtime/memory:make-rt-heap :young-size 128 :old-size 128)))
    (cl-cc/runtime/memory:rt-gc-major-collect heap)
    (expect (cl-cc/runtime/memory:rt-heap-gc-state heap) :to-be :normal)))

(it-sequential "gc-major-collect-reclaims-unreachable-old-object"
  (let ((cl-cc/runtime/memory:*gc-compaction-enabled* nil))
    (let* ((heap (cl-cc/runtime/memory:make-rt-heap :young-size 128 :old-size 128))
           (old-base (cl-cc/runtime/memory:rt-heap-old-base heap)))
      (cl-cc/runtime/memory:rt-heap-set-header
       heap old-base
       (cl-cc/runtime/memory:make-rt-header 3 1 :gc-bits 0))
      (setf (cl-cc/runtime/memory:rt-heap-old-free heap) (+ old-base 3))
      (cl-cc/runtime/memory:rt-gc-major-collect heap)
      (expect (>= (cl-cc/runtime/memory:rt-heap-words-collected heap) 3)
              :to-be-truthy))))

(it-sequential "gc-major-collect-preserves-rooted-old-object"
  (let ((cl-cc/runtime/memory:*gc-compaction-enabled* nil))
    (let* ((heap (cl-cc/runtime/memory:make-rt-heap :young-size 128 :old-size 128))
           (old-base (cl-cc/runtime/memory:rt-heap-old-base heap))
           (root (cons nil old-base)))
      (cl-cc/runtime/memory:rt-heap-set-header
       heap old-base
       (cl-cc/runtime/memory:make-rt-header 3 1 :gc-bits 0))
      (setf (cl-cc/runtime/memory:rt-heap-old-free heap) (+ old-base 3))
      (cl-cc/runtime/memory:rt-gc-add-root heap root)
      (cl-cc/runtime/memory:rt-gc-major-collect heap)
      (let* ((snapshot (cl-cc/runtime/memory:rt-gc-heap-snapshot heap))
             (objects (getf snapshot :objects))
             (object (find (cdr root) objects
                           :key (lambda (item) (getf item :address)))))
        (expect object :to-be-truthy)
        (expect (= 3 (getf object :size-words)) :to-be-truthy))
      (cl-cc/runtime/memory:rt-gc-remove-root heap root))))

(it-sequential "gc-major-collect-stats-major-count"
  (let ((cl-cc/runtime/memory:*rt-concurrent-gc-enabled-p* nil)
        (heap (cl-cc/runtime/memory:make-rt-heap :young-size 128 :old-size 128)))
    (cl-cc/runtime/memory:rt-gc-major-collect heap)
    (cl-cc/runtime/memory:rt-gc-major-collect heap)
    (expect (= 2 (getf (cl-cc/runtime/memory:rt-gc-stats heap) :major-gc-count))
            :to-be-truthy)))

(it-sequential "gc-configure-concurrent-mode-updates-runtime-flags"
  (let ((cl-cc/runtime/memory:*rt-concurrent-gc-enabled-p* nil)
        (cl-cc/runtime/memory:*rt-concurrent-gc-write-barrier-mode* :satb)
        (cl-cc/runtime/memory:*rt-concurrent-gc-stw-phases* nil)
        (cl-cc/runtime/memory:*rt-concurrent-gc-mutator-assist-p* nil))
    (let* ((heap (cl-cc/runtime/memory:make-rt-heap :young-size 128 :old-size 128)))
      (cl-cc/runtime/memory:rt-gc-configure-concurrent-mode
       :enabled-p t
       :write-barrier :satb
       :stw-phases (list :initial-mark :final-remark)
       :mutator-assist-p t)
      (let ((stats (cl-cc/runtime/memory:rt-gc-stats heap)))
        (expect (getf stats :concurrent-gc-enabled-p) :to-be-truthy)
        (expect (getf stats :concurrent-gc-write-barrier) :to-be :satb)
        (expect (getf stats :concurrent-gc-stw-phases) :to-equal (list :initial-mark :final-remark))
        (expect (getf stats :concurrent-gc-mutator-assist-p) :to-be-truthy)))))

(it-sequential "gc-major-collect-enters-concurrent-state-when-enabled"
  (let ((cl-cc/runtime/memory:*rt-concurrent-gc-enabled-p* nil)
        (heap (cl-cc/runtime/memory:make-rt-heap :young-size 128 :old-size 128)))
    (cl-cc/runtime/memory:rt-gc-configure-concurrent-mode :enabled-p t)
    (cl-cc/runtime/memory:rt-gc-major-collect heap)
    (expect (cl-cc/runtime/memory:rt-heap-gc-state heap) :to-be :normal)
    (expect (getf (cl-cc/runtime/memory:rt-gc-stats heap) :concurrent-gc-enabled-p)
            :to-be-truthy)))

(it-sequential "gc-concurrent-assist-marks-satb-old-pointers-with-budget"
  (let ((cl-cc/runtime/memory:*rt-concurrent-gc-enabled-p* nil)
        (cl-cc/runtime/memory:*rt-concurrent-gc-mutator-assist-p* nil))
    (let* ((heap (cl-cc/runtime/memory:make-rt-heap :young-size 128 :old-size 128))
           (old-base (cl-cc/runtime/memory:rt-heap-old-base heap))
           (a old-base)
           (b (+ old-base 3)))
      (cl-cc/runtime/memory:rt-heap-set-header
       heap a (cl-cc/runtime/memory:make-rt-header 3 1 :gc-bits 0))
      (cl-cc/runtime/memory:rt-heap-set-header
       heap b (cl-cc/runtime/memory:make-rt-header 3 1 :gc-bits 0))
      (setf (cl-cc/runtime/memory:rt-heap-old-free heap) (+ old-base 6))
      (cl-cc/runtime/memory:rt-gc-satb-enqueue heap a)
      (cl-cc/runtime/memory:rt-gc-satb-enqueue heap b)
      (cl-cc/runtime/memory:rt-gc-configure-concurrent-mode
       :enabled-p t
       :mutator-assist-p t)
      (setf (cl-cc/runtime/memory:rt-heap-gc-state heap) :major-gc-concurrent)
      (expect (= 1 (cl-cc/runtime/memory:rt-gc-concurrent-assist heap :budget 1))
              :to-be-truthy)
      (expect (null (cl-cc/runtime/memory:rt-gc-drain-satb-thread-queues heap))
              :to-be-truthy)
      (cl-cc/runtime/memory:rt-gc-concurrent-assist heap :budget 2)
      (cl-cc/runtime/memory:rt-gc-concurrent-sweep heap)
      (expect (= 2 (getf (cl-cc/runtime/memory:rt-gc-heap-census heap) :cons-count))
              :to-be-truthy))))
