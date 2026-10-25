;;;; tests/gc-stats-tests.lisp — GC Statistics Tests
;;;;
;;;; Continuation of gc-tests.lisp.
;;;; Tests for rt-gc-stats plist structure and correctness.

(in-package :cl-cc/runtime/memory/test)


;;; ------------------------------------------------------------
;;; Test 8: gc-stats
;;; ------------------------------------------------------------

(it-sequential "gc-stats-returns-plist"
  (let* ((heap (cl-cc/runtime/memory:make-rt-heap :young-size 32 :old-size 32))
         (stats (cl-cc/runtime/memory:rt-gc-stats heap)))
    (expect (getf stats :minor-gc-count) :to-be-truthy)
    (expect (listp stats) :to-be-truthy)
    (expect (member :minor-gc-count  stats) :to-be-truthy)
    (expect (member :major-gc-count  stats) :to-be-truthy)
    (expect (member :words-collected stats) :to-be-truthy)
    (expect (member :words-promoted  stats) :to-be-truthy)
    (expect (member :young-used      stats) :to-be-truthy)
    (expect (member :young-total     stats) :to-be-truthy)
    (expect (member :old-used        stats) :to-be-truthy)
    (expect (member :old-total       stats) :to-be-truthy)
     (expect (member :heap-occupancy-pct stats) :to-be-truthy)
     (expect (member :free-list-count stats) :to-be-truthy)))

(it-sequential "gc-stats-public-facade-returns-fr-356-keys"
  (let* ((heap (cl-cc/runtime/memory:make-rt-heap :young-size 32 :old-size 32))
         (stats (cl-cc/runtime/memory:rt-gc-stats heap)))
    (expect (member :minor-gcs stats) :to-be-truthy)
    (expect (member :major-gcs stats) :to-be-truthy)
    (expect (member :total-collected-bytes stats) :to-be-truthy)
    (expect (member :pause-ms-p99 stats) :to-be-truthy)
    (expect (= 0 (getf stats :minor-gcs)) :to-be-truthy)
    (expect (= 0 (getf stats :major-gcs)) :to-be-truthy)
    (expect (= 0 (getf stats :total-collected-bytes)) :to-be-truthy)))

(it-sequential "gc-stats-minor-gc-count-increments"
  (let* ((heap (cl-cc/runtime/memory:make-rt-heap :young-size 32 :old-size 32)))
    (let ((addr (cl-cc/runtime/memory:rt-gc-alloc heap 1 3)))
      (cl-cc/runtime/memory:rt-heap-set-header heap addr (cl-cc/runtime/memory:make-rt-header 3 1 :gc-bits 0))
      (let ((root (cons nil addr)))
        (cl-cc/runtime/memory:rt-gc-add-root heap root)
        (cl-cc/runtime/memory:rt-gc-minor-collect heap)
        (expect (= 1 (getf (cl-cc/runtime/memory:rt-gc-stats heap) :minor-gc-count)) :to-be-truthy)
        (cl-cc/runtime/memory:rt-gc-remove-root heap root)))))

(it-sequential "gc-stats-totals-match-heap-structure"
  (let* ((heap  (cl-cc/runtime/memory:make-rt-heap :young-size 32 :old-size 32))
         (stats (cl-cc/runtime/memory:rt-gc-stats heap)))
    (expect (= (cl-cc/runtime/memory:rt-heap-young-semi-size heap) (getf stats :young-total)) :to-be-truthy)
    (expect (= (cl-cc/runtime/memory:rt-heap-old-size heap) (getf stats :old-total)) :to-be-truthy)))

(it-sequential "gc-stats-young-used-after-alloc"
  (let* ((heap (cl-cc/runtime/memory:make-rt-heap :young-size 32 :old-size 32)))
    (cl-cc/runtime/memory:rt-gc-alloc heap 1 3)
    (cl-cc/runtime/memory:rt-gc-alloc heap 1 3)
    (expect (= 6 (getf (cl-cc/runtime/memory:rt-gc-stats heap) :young-used)) :to-be-truthy)))

(it-sequential "rt-heap-occupancy-pct-combines-young-and-old-usage"
  (let* ((heap (cl-cc/runtime/memory:make-rt-heap :young-size 40 :old-size 30))
         (old-base (cl-cc/runtime/memory:rt-heap-old-base heap)))
    (cl-cc/runtime/memory:rt-gc-alloc heap 1 5)
    (setf (cl-cc/runtime/memory:rt-heap-old-free heap) (+ old-base 10))
    (expect (= 30.0d0 (cl-cc/runtime/memory:rt-heap-occupancy-pct heap)) :to-be-truthy)
    (expect (= 30.0d0 (getf (cl-cc/runtime/memory:rt-gc-stats heap)
                           :heap-occupancy-pct)) :to-be-truthy)))

(it-sequential "rt-gc-profile-samples-allocation-sites"
  (let ((heap (cl-cc/runtime/memory:make-rt-heap :young-size 32 :old-size 32))
        (cl-cc/runtime/memory:*gc-profile-enabled* t)
        (cl-cc/runtime/memory:*gc-profile-interval* 16))
    (cl-cc/runtime/memory:rt-gc-alloc heap 1 2)
    (let ((report (cl-cc/runtime/memory:rt-gc-profile-report)))
      (expect (getf report :enabled-p) :to-be-truthy)
      (expect (some (lambda (spot)
                      (eq (getf spot :function) :unknown))
                    (getf report :hot-spots))
              :to-be-truthy))))
