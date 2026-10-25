(in-package :cl-cc/runtime/memory/test)

(it-sequential "runtime-arena-allocator-bulk-reset"
  :timeout
  5
  (cl-cc/runtime/memory:with-arena (arena :size-hint 2)
    (let ((a (cl-cc/runtime/memory:arena-alloc arena 1))
          (b (cl-cc/runtime/memory:arena-alloc arena 3)))
      (expect (= 0 (cl-cc/runtime/memory:rt-arena-block-offset a)) :to-be-truthy)
      (expect (= 1 (cl-cc/runtime/memory:rt-arena-block-offset b)) :to-be-truthy)
      (expect (= 4 (cl-cc/runtime/memory:rt-arena-cursor arena)) :to-be-truthy)
      (cl-cc/runtime/memory:arena-reset arena)
      (expect (= 0 (cl-cc/runtime/memory:rt-arena-cursor arena)) :to-be-truthy))))

(it-sequential "runtime-object-pool-two-tier-reuse"
  :timeout
  5
  (let* ((pool (cl-cc/runtime/memory:make-object-pool :test-vector
                                                      :min-size 1
                                                      :max-size 4
                                                      :constructor (lambda () (vector :fresh))))
         (obj (cl-cc/runtime/memory:pool-acquire pool)))
    (cl-cc/runtime/memory:pool-release pool obj)
    (expect (cl-cc/runtime/memory:pool-acquire pool) :to-be obj)))

(it-sequential "runtime-gc-heap-configuration"
  :timeout
  5
  (let ((old-young cl-cc/runtime/memory:*gc-young-size-words*)
        (old-old cl-cc/runtime/memory:*gc-old-size-words*))
    (unwind-protect
         (let ((heap (cl-cc/runtime/memory:make-rt-heap)))
           (cl-cc/runtime/memory:rt-gc-major-collect heap)
           (let ((stats (cl-cc/runtime/memory:rt-gc-stats heap)))
             (expect (and (= (* 2 (getf stats :young-total))
                             cl-cc/runtime/memory:*gc-young-size-words*)
                          (= (getf stats :old-total)
                             cl-cc/runtime/memory:*gc-old-size-words*)
                          (plusp (getf stats :young-total))
                          (plusp (getf stats :old-total)))
                     :to-be-truthy)
             (expect (and (numberp cl-cc/runtime/memory:*gc-nursery-size*)
                          (plusp cl-cc/runtime/memory:*gc-nursery-size*))
                     :to-be-truthy)
             (expect (and (numberp cl-cc/runtime/memory:*gc-pause-target-ms*)
                          (plusp cl-cc/runtime/memory:*gc-pause-target-ms*))
                     :to-be-truthy)
             (expect (member (cl-cc/runtime/memory:rt-gc-select-policy heap)
                             (list :minor :major :compact))
                     :to-be-truthy)
             (expect (and (numberp (getf stats :gc-pause-total))
                          (>= (getf stats :gc-pause-total) 0)
                          (numberp (getf stats :gc-pause-max))
                          (>= (getf stats :gc-pause-max) 0))
                     :to-be-truthy)))
      (setf cl-cc/runtime/memory:*gc-young-size-words* old-young
            cl-cc/runtime/memory:*gc-old-size-words* old-old))))
