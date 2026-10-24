(in-package :cl-cc/runtime/memory/test)

(describe
  "out-of-memory signalling (runtime-stack.lisp)"
  (it
    "rt-signal-oom raises rt-oom-condition carrying the supplied words"
    (expect
      (handler-case (cl-cc/runtime::rt-signal-oom 100 :limit-words 1000 :used-words 500)
        (cl-cc/runtime::rt-oom-condition (c)
          (list
            (cl-cc/runtime::rt-oom-requested-words c)
            (cl-cc/runtime::rt-oom-limit-words c)
            (cl-cc/runtime::rt-oom-used-words c))))
      :to-equal
      '(100 1000 500)))
  (it
    "rt-signal-oom derives limit and used words from a heap"
    (let ((heap (cl-cc/runtime::make-rt-heap)))
      (handler-case (cl-cc/runtime::rt-signal-oom 8 :heap heap)
        (cl-cc/runtime::rt-oom-condition (c)
          (expect (cl-cc/runtime::rt-oom-requested-words c) :to-be 8)
          (expect (integerp (cl-cc/runtime::rt-oom-used-words c)) :to-be-truthy))))))

(describe "heap-pressure thresholds (runtime-stack.lisp)"
  (it "a fresh, near-empty heap returns an occupancy number and warns at nothing"
    (let ((heap (cl-cc/runtime::make-rt-heap))
          (warned 0))
      (handler-bind ((cl-cc/runtime::rt-gc-pressure-warning
                       (lambda (c) (declare (ignore c)) (incf warned) (muffle-warning))))
        (expect (numberp (cl-cc/runtime::rt-check-heap-pressure-thresholds heap))
                :to-be-truthy))
      (expect warned :to-be 0)))

  (it "a fully occupied heap crosses all three (80/90/95) thresholds"
    (let ((heap (cl-cc/runtime::make-rt-heap))
          (warned 0))
      ;; Force 100% occupancy by advancing the young and old allocation cursors.
      (setf (cl-cc/runtime::rt-heap-young-free heap)
            (+ (cl-cc/runtime::rt-heap-young-from-base heap)
               (cl-cc/runtime::rt-heap-young-semi-size heap))
            (cl-cc/runtime::rt-heap-old-free heap)
            (+ (cl-cc/runtime::rt-heap-old-base heap)
               (cl-cc/runtime::rt-heap-old-size heap)))
      (handler-bind ((cl-cc/runtime::rt-gc-pressure-warning
                       (lambda (c) (declare (ignore c)) (incf warned) (muffle-warning))))
        (cl-cc/runtime::rt-check-heap-pressure-thresholds heap))
      (expect warned :to-be 3))))
