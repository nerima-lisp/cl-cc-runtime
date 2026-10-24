;;;; gc-heap-verify.lisp — Heap consistency verification (rt-gc-verify-heap),
;;;; split out of gc-roots-objects.lisp
(in-package :cl-cc/runtime)

(defun rt-gc-verify-heap (heap)
  "Verify basic heap invariants and signal an error on corruption."
  (labels ((verify-range (start end evacuated-p)
             (loop with addr = start
                   while (< addr end) do
                     (let ((h (rt-heap-object-header heap addr)))
                       (when (and evacuated-p (header-forwarding-p h))
                         (error "GC verify: forwarding pointer remains at ~D" addr))
                       (cond
                         ((header-forwarding-p h)
                          (if evacuated-p
                              (error "GC verify: forwarding pointer remains at ~D" addr)
                              (incf addr 1)))
                         ((and (integerp h) (zerop h)) (return))
                         ((not (%rt-gc-valid-header-p h))
                          (error "GC verify: invalid header at ~D: ~S" addr h))
                          (t
                           (let ((size (rt-header-size h)))
                             (when (> (+ addr size) end)
                               (error "GC verify: object at ~D exceeds range" addr))
                             (when (or (header-marked-p h) (header-gray-p h))
                               (error "GC verify: mark/gray bits not cleared at ~D" addr))
                             (dolist (offset (rt-object-pointer-slots heap addr))
                               (let ((value (rt-heap-ref heap (+ addr offset))))
                                 (when (and (integerp value) (val-pointer-p value))
                                   (let ((target (decode-pointer value)))
                                     (unless (%rt-gc-object-start-p heap target)
                                       (error "GC verify: invalid boxed pointer ~S at ~D+~D"
                                              value addr offset))))
                                 (when (and (integerp value)
                                            (not (val-pointer-p value))
                                            (rt-heap-addr-p heap value)
                                            (not (%rt-gc-object-start-p heap value)))
                                   (error "GC verify: invalid raw pointer ~S at ~D+~D"
                                          value addr offset))))
                             (incf addr size))))))))
    (verify-range (rt-heap-young-from-base heap) (rt-heap-young-free heap) nil)
    (verify-range (rt-heap-old-base heap) (rt-heap-old-free heap) t)
    (verify-range (rt-heap-large-obj-base heap) (rt-heap-large-obj-free heap) t)
    t))
