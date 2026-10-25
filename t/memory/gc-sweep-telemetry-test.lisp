;;;; t/gc-sweep-telemetry-test.lisp — GC Statistics Tests
;;;;
;;;; Continuation of gc-minor-test.lisp.
;;;; Tests for rt-gc-stats plist structure and correctness.
(in-package :cl-cc/runtime/memory/test)

;;; ------------------------------------------------------------
;;; Test 8: gc-stats
;;; ------------------------------------------------------------
(it-sequential
  "rt-gc-stats returns a plist with all required keys."
  (let* ((heap (%make-small-heap))
         (stats (cl-cc/runtime/memory:rt-gc-stats heap)))
    (expect (getf stats :minor-gc-count) :to-be-truthy)
    (expect (listp stats) :to-be-truthy)
    (expect (member :minor-gc-count stats) :to-be-truthy)
    (expect (member :major-gc-count stats) :to-be-truthy)
    (expect (member :words-collected stats) :to-be-truthy)
    (expect (member :words-promoted stats) :to-be-truthy)
    (expect (member :young-used stats) :to-be-truthy)
    (expect (member :young-total stats) :to-be-truthy)
    (expect (member :old-used stats) :to-be-truthy)
    (expect (member :old-total stats) :to-be-truthy)
    (expect (member :heap-occupancy-pct stats) :to-be-truthy)
    (expect (member :free-list-count stats) :to-be-truthy)))

(it-sequential
  "After one minor GC, :minor-gc-count is 1."
  (let* ((heap (%make-small-heap)))
    (let ((addr (cl-cc/runtime/memory:rt-gc-alloc heap cl-cc/runtime/values:+rt-tag-cons+ 3)))
      (%write-header heap addr 3 cl-cc/runtime/values:+rt-tag-cons+)
      (let ((root (cons nil addr)))
        (cl-cc/runtime/memory:rt-gc-add-root heap root)
        (cl-cc/runtime/memory:rt-gc-minor-collect heap)
        (expect (getf (cl-cc/runtime/memory:rt-gc-stats heap) :minor-gc-count) :to-equal 1)
        (cl-cc/runtime/memory:rt-gc-remove-root heap root)))))

(it-sequential
  ":young-total matches semi-size; :old-total matches old-size slot."
  (let* ((heap (%make-small-heap))
         (stats (cl-cc/runtime/memory:rt-gc-stats heap)))
    (expect
      (getf stats :young-total)
      :to-equal
      (cl-cc/runtime/memory:rt-heap-young-semi-size heap))
    (expect
      (getf stats :old-total)
      :to-equal
      (cl-cc/runtime/memory:rt-heap-old-size heap))))

(it-sequential
  ":young-used reflects allocated words before GC."
  (let* ((heap (%make-small-heap)))
    (cl-cc/runtime/memory:rt-gc-alloc heap cl-cc/runtime/values:+rt-tag-cons+ 3)
    (cl-cc/runtime/memory:rt-gc-alloc heap cl-cc/runtime/values:+rt-tag-cons+ 3)
    (expect (getf (cl-cc/runtime/memory:rt-gc-stats heap) :young-used) :to-equal 6)))

(it-sequential
  "rt-heap-occupancy-pct reports young+old usage over one young semi-space plus old capacity."
  (let* ((heap (cl-cc/runtime/memory:make-rt-heap :young-size 40 :old-size 30))
         (old-base (cl-cc/runtime/memory:rt-heap-old-base heap)))
    (cl-cc/runtime/memory:rt-gc-alloc heap cl-cc/runtime/values:+rt-tag-cons+ 5)
    (setf (cl-cc/runtime/memory:rt-heap-old-free heap) (+ old-base 10))
    (expect (cl-cc/runtime/memory:rt-heap-occupancy-pct heap) :to-equal 30.0d0)
    (expect
      (getf (cl-cc/runtime/memory:rt-gc-stats heap) :heap-occupancy-pct)
      :to-equal
      30.0d0)))

(it-sequential
  "rt-gc-alloc feeds the runtime allocation profiler when sampling is enabled."
  (let ((heap (%make-small-heap))
        (cl-cc/runtime/memory:*gc-profile-enabled* t)
        (cl-cc/runtime/memory:*gc-profile-interval* 16)
        (*gc-profile-bytes-since-sample* 0)
        (*gc-profile-samples* (make-hash-table :test #'equal))
        (*gc-profile-current-function* :profile-test))
    (cl-cc/runtime/memory:rt-gc-alloc heap cl-cc/runtime/values:+rt-tag-cons+ 2)
    (let ((report (cl-cc/runtime/memory:rt-gc-profile-report)))
      (expect (getf report :enabled-p) :to-be-truthy)
      (expect
        (getf report :hot-spots)
        :to-equal
        (list (list :function :profile-test :count 1))))))
