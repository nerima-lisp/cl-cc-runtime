;;;; tests/gc-major-sweep-extra-tests.lisp — Coverage for src/gc-major-sweep.lisp
;;;;
;;;; Targets the gaps left by gc-sweep-major-tests.lisp: lazy page-granular
;;;; sweeping, free-list coalescing, the concurrent-sweep worker/driver, sliding
;;;; compaction, and the compaction trigger policy.

(in-package :cl-cc-runtime/test)

(in-suite gc-suite)

(defun %gms-put-object (heap addr &key marked)
  "Write a 3-word cons-tagged object header at ADDR, optionally marked."
  (let ((h (cl-cc/runtime::make-rt-header 3 cl-cc/runtime:+rt-tag-cons+ :gc-bits 0)))
    (cl-cc/runtime::rt-heap-set-header
     heap addr (if marked (cl-cc/runtime::header-set-mark h) h))))

;;; ------------------------------------------------------------
;;; Free-list coalescing (pure)
;;; ------------------------------------------------------------

(deftest gms-coalesce-merges-adjacent
  "%gc-coalesce-free-list merges blocks whose ranges touch."
  (assert-equal '((5 . 10))
                (cl-cc/runtime::%gc-coalesce-free-list '((2 . 10) (3 . 12)))))

(deftest gms-coalesce-keeps-non-adjacent
  "Non-adjacent blocks are returned sorted by address, unmerged."
  (assert-equal '((2 . 10) (3 . 20))
                (cl-cc/runtime::%gc-coalesce-free-list '((3 . 20) (2 . 10)))))

(deftest gms-coalesce-empty
  "Coalescing an empty free-list yields NIL."
  (assert-null (cl-cc/runtime::%gc-coalesce-free-list nil)))

;;; ------------------------------------------------------------
;;; Lazy page sweep
;;; ------------------------------------------------------------

(deftest gms-lazy-sweep-step-reclaims-dead
  "rt-gc-lazy-sweep-step frees an unmarked object and reports the freed words."
  (let* ((heap (cl-cc/runtime::make-rt-heap :young-size 64 :old-size 64))
         (old-base (cl-cc/runtime::rt-heap-old-base heap)))
    (%gms-put-object heap old-base)
    (setf (cl-cc/runtime::rt-heap-old-free heap) (+ old-base 3))
    (assert-= 3 (cl-cc/runtime::rt-gc-lazy-sweep-step heap old-base))
    (assert-true (>= (cl-cc/runtime::rt-heap-words-collected heap) 3))))

(deftest gms-lazy-sweep-step-preserves-live
  "rt-gc-lazy-sweep-step keeps a marked object and clears its mark bit."
  (let* ((heap (cl-cc/runtime::make-rt-heap :young-size 64 :old-size 64))
         (old-base (cl-cc/runtime::rt-heap-old-base heap)))
    (%gms-put-object heap old-base :marked t)
    (setf (cl-cc/runtime::rt-heap-old-free heap) (+ old-base 3))
    (assert-= 0 (cl-cc/runtime::rt-gc-lazy-sweep-step heap old-base))
    (assert-false (cl-cc/runtime::header-marked-p
                   (cl-cc/runtime::rt-heap-object-header heap old-base)))))

;;; ------------------------------------------------------------
;;; Concurrent sweep worker / driver
;;; ------------------------------------------------------------

(deftest gms-concurrent-sweep-worker-reclaims
  "rt-gc-concurrent-sweep-worker sweeps old space and returns the heap."
  (let ((cl-cc/runtime::*gc-lazy-sweep-enabled* nil))
    (let* ((heap (cl-cc/runtime::make-rt-heap :young-size 64 :old-size 64))
           (old-base (cl-cc/runtime::rt-heap-old-base heap)))
      (%gms-put-object heap old-base)
      (setf (cl-cc/runtime::rt-heap-old-free heap) (+ old-base 3))
      (assert-eq heap (cl-cc/runtime::rt-gc-concurrent-sweep-worker heap))
      (assert-true (>= (cl-cc/runtime::rt-heap-words-collected heap) 3)))))

(deftest gms-concurrent-sweep-driver-reclaims
  "rt-gc-concurrent-sweep runs the sweep worker (on a host thread) to completion."
  (let ((cl-cc/runtime::*gc-lazy-sweep-enabled* nil))
    (let* ((heap (cl-cc/runtime::make-rt-heap :young-size 64 :old-size 64))
           (old-base (cl-cc/runtime::rt-heap-old-base heap)))
      (%gms-put-object heap old-base)
      (setf (cl-cc/runtime::rt-heap-old-free heap) (+ old-base 3))
      (cl-cc/runtime::rt-gc-concurrent-sweep heap)
      (assert-true (>= (cl-cc/runtime::rt-heap-words-collected heap) 3)))))

;;; ------------------------------------------------------------
;;; Sliding compaction
;;; ------------------------------------------------------------

(deftest gms-compact-old-space-returns-status
  "rt-gc-compact-old-space walks live old objects and reports a done status."
  (let ((cl-cc/runtime::*rt-global-var-registry* (make-hash-table :test #'eq)))
    (let* ((heap (cl-cc/runtime::make-rt-heap :young-size 128 :old-size 128))
           (old-base (cl-cc/runtime::rt-heap-old-base heap)))
      (%gms-put-object heap old-base :marked t)
      (%gms-put-object heap (+ old-base 3) :marked t)
      (setf (cl-cc/runtime::rt-heap-old-free heap) (+ old-base 6))
      (let ((result (cl-cc/runtime::rt-gc-compact-old-space heap)))
        (assert-eq :compact-done (getf result :status))
        (assert-= 2 (getf result :live-count))))))

;;; ------------------------------------------------------------
;;; Compaction trigger policy
;;; ------------------------------------------------------------

(deftest gms-should-run-compaction-disabled
  "rt-gc-should-run-compaction-p is false when compaction is globally disabled."
  (let ((cl-cc/runtime::*gc-compaction-enabled* nil))
    (let ((heap (cl-cc/runtime::make-rt-heap :young-size 64 :old-size 64)))
      (assert-false (cl-cc/runtime::rt-gc-should-run-compaction-p heap)))))

(deftest gms-should-run-compaction-by-cycle
  "Compaction is triggered when major-gc-count hits the configured cycle period."
  (let ((cl-cc/runtime::*gc-compaction-enabled* t)
        (cl-cc/runtime::*gc-compact-after-major-cycles* 2))
    (let ((heap (cl-cc/runtime::make-rt-heap :young-size 64 :old-size 64)))
      (setf (cl-cc/runtime::rt-heap-major-gc-count heap) 2)
      (assert-true (cl-cc/runtime::rt-gc-should-run-compaction-p heap)))))
