;;;; t/gc-major-sweep-incremental-test.lisp — Coverage for src/gc-major-sweep.lisp
;;;;
;;;; Targets the gaps left by gc-major-sweep-test.lisp: lazy page-granular
;;;; sweeping, free-list coalescing, the concurrent-sweep worker/driver, sliding
;;;; compaction, and the compaction trigger policy.
(in-package :cl-cc-runtime/test)

(defun %gms-put-object (heap addr &key marked)
  "Write a 3-word cons-tagged object header at ADDR, optionally marked."
  (let ((h (cl-cc/runtime::make-rt-header 3 cl-cc/runtime:+rt-tag-cons+ :gc-bits 0)))
    (cl-cc/runtime::rt-heap-set-header
      heap
      addr
      (if marked (cl-cc/runtime::header-set-mark h)
        h))))

;;; ------------------------------------------------------------
;;; Free-list coalescing (pure)
;;; ------------------------------------------------------------
(it-sequential
  "%gc-coalesce-free-list merges blocks whose ranges touch."
  (expect
    (cl-cc/runtime::%gc-coalesce-free-list '((2 . 10) (3 . 12)))
    :to-equal
    '((5 . 10))))

(it-sequential
  "Non-adjacent blocks are returned sorted by address, unmerged."
  (expect
    (cl-cc/runtime::%gc-coalesce-free-list '((3 . 20) (2 . 10)))
    :to-equal
    '((2 . 10) (3 . 20))))

(it-sequential
  "Coalescing an empty free-list yields NIL."
  (expect (cl-cc/runtime::%gc-coalesce-free-list nil) :to-be-null))

;;; ------------------------------------------------------------
;;; Lazy page sweep
;;; ------------------------------------------------------------
(it-sequential
  "rt-gc-lazy-sweep-step frees an unmarked object and reports the freed words."
  (let* ((heap (cl-cc/runtime::make-rt-heap :young-size 64 :old-size 64))
         (old-base (cl-cc/runtime::rt-heap-old-base heap)))
    (%gms-put-object heap old-base)
    (setf (cl-cc/runtime::rt-heap-old-free heap) (+ old-base 3))
    (expect (cl-cc/runtime::rt-gc-lazy-sweep-step heap old-base) :to-equal 3)
    (expect (>= (cl-cc/runtime::rt-heap-words-collected heap) 3) :to-be-truthy)))

(it-sequential
  "rt-gc-lazy-sweep-step keeps a marked object and clears its mark bit."
  (let* ((heap (cl-cc/runtime::make-rt-heap :young-size 64 :old-size 64))
         (old-base (cl-cc/runtime::rt-heap-old-base heap)))
    (%gms-put-object heap old-base :marked t)
    (setf (cl-cc/runtime::rt-heap-old-free heap) (+ old-base 3))
    (expect (cl-cc/runtime::rt-gc-lazy-sweep-step heap old-base) :to-equal 0)
    (expect
      (cl-cc/runtime::header-marked-p
        (cl-cc/runtime::rt-heap-object-header heap old-base))
      :to-be-falsy)))

;;; ------------------------------------------------------------
;;; Concurrent sweep worker / driver
;;; ------------------------------------------------------------
(it-sequential
  "rt-gc-concurrent-sweep-worker sweeps old space and returns the heap."
  (let ((cl-cc/runtime::*gc-lazy-sweep-enabled* nil))
    (let* ((heap (cl-cc/runtime::make-rt-heap :young-size 64 :old-size 64))
           (old-base (cl-cc/runtime::rt-heap-old-base heap)))
      (%gms-put-object heap old-base)
      (setf (cl-cc/runtime::rt-heap-old-free heap) (+ old-base 3))
      (expect (cl-cc/runtime::rt-gc-concurrent-sweep-worker heap) :to-be heap)
      (expect (>= (cl-cc/runtime::rt-heap-words-collected heap) 3) :to-be-truthy))))

(it-sequential
  "rt-gc-concurrent-sweep runs the sweep worker (on a host thread) to completion."
  (let ((cl-cc/runtime::*gc-lazy-sweep-enabled* nil))
    (let* ((heap (cl-cc/runtime::make-rt-heap :young-size 64 :old-size 64))
           (old-base (cl-cc/runtime::rt-heap-old-base heap)))
      (%gms-put-object heap old-base)
      (setf (cl-cc/runtime::rt-heap-old-free heap) (+ old-base 3))
      (cl-cc/runtime::rt-gc-concurrent-sweep heap)
      (expect (>= (cl-cc/runtime::rt-heap-words-collected heap) 3) :to-be-truthy))))

;;; ------------------------------------------------------------
;;; Sliding compaction
;;; ------------------------------------------------------------
(it-sequential
  "rt-gc-compact-old-space walks live old objects and reports a done status."
  (let ((cl-cc/runtime::*rt-global-var-registry* (make-hash-table :test #'eq)))
    (let* ((heap (cl-cc/runtime::make-rt-heap :young-size 128 :old-size 128))
           (old-base (cl-cc/runtime::rt-heap-old-base heap)))
      (%gms-put-object heap old-base :marked t)
      (%gms-put-object heap (+ old-base 3) :marked t)
      (setf (cl-cc/runtime::rt-heap-old-free heap) (+ old-base 6))
      (let ((result (cl-cc/runtime::rt-gc-compact-old-space heap)))
        (expect (getf result :status) :to-be :compact-done)
        (expect (getf result :live-count) :to-equal 2)))))

;;; ------------------------------------------------------------
;;; Compaction trigger policy
;;; ------------------------------------------------------------
(it-sequential
  "rt-gc-should-run-compaction-p is false when compaction is globally disabled."
  (let ((cl-cc/runtime::*gc-compaction-enabled* nil))
    (let ((heap (cl-cc/runtime::make-rt-heap :young-size 64 :old-size 64)))
      (expect (cl-cc/runtime::rt-gc-should-run-compaction-p heap) :to-be-falsy))))

(it-sequential
  "Compaction is triggered when major-gc-count hits the configured cycle period."
  (let ((cl-cc/runtime::*gc-compaction-enabled* t)
        (cl-cc/runtime::*gc-compact-after-major-cycles* 2))
    (let ((heap (cl-cc/runtime::make-rt-heap :young-size 64 :old-size 64)))
      (setf (cl-cc/runtime::rt-heap-major-gc-count heap) 2)
      (expect (cl-cc/runtime::rt-gc-should-run-compaction-p heap) :to-be-truthy))))
