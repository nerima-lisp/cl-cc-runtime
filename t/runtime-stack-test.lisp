;;;; t/runtime-stack-test.lisp — stack-depth guard, return-address poisoning,
;;;; OOM / GC-pressure conditions (src/runtime-stack.lisp).
(in-package :cl-cc-runtime/test)

(describe "return-address poisoning (runtime-stack.lisp)"
  (it "poison then unpoison is the identity"
    (dolist (n '(0 1 42 #x1234 #xdeadbeef #xfffffffffffff))
      (expect (cl-cc/runtime::rt-unpoison-return-address
               (cl-cc/runtime::rt-poison-return-address n))
              :to-be n)))

  (it "a poisoned address is recognised as poisoned"
    (expect (cl-cc/runtime::rt-return-address-poisoned-p
             (cl-cc/runtime::rt-poison-return-address 0))
            :to-be-truthy))

  (it "a raw small address is not flagged as poisoned"
    (expect (cl-cc/runtime::rt-return-address-poisoned-p 4096) :to-be-null))

  (it "poisoning a non-integer signals a type error"
    (expect (handler-case (progn (cl-cc/runtime::rt-poison-return-address :not-an-int) nil)
              (type-error () t))
            :to-be-truthy))

  (it-property "poison/unpoison round-trips arbitrary addresses"
      ((addr (gen-integer :min 0 :max #xffffffffffff)))
    (expect (cl-cc/runtime::rt-unpoison-return-address
             (cl-cc/runtime::rt-poison-return-address addr))
            :to-be addr)))

(describe "stack-overflow guard (runtime-stack.lisp)"
  (it "rt-check-stack-overflow returns the depth when below the limit"
    (let ((cl-cc/runtime::*max-call-stack-depth* 10))
      (expect (cl-cc/runtime::rt-check-stack-overflow 3) :to-be 3)))

  (it "rt-check-stack-overflow signals at the limit"
    (let ((cl-cc/runtime::*max-call-stack-depth* 5))
      (expect (handler-case (progn (cl-cc/runtime::rt-check-stack-overflow 5) nil)
                (cl-cc/runtime::rt-stack-overflow () t))
              :to-be-truthy)))

  (it "the signalled condition carries the offending depth and limit"
    (let ((cl-cc/runtime::*max-call-stack-depth* 7))
      (handler-case (cl-cc/runtime::rt-check-stack-overflow 7)
        (cl-cc/runtime::rt-stack-overflow (c)
          (expect (cl-cc/runtime::rt-stack-overflow-depth c) :to-be 7)
          (expect (cl-cc/runtime::rt-stack-overflow-limit c) :to-be 7)))))

  (it "rt-with-call-stack-guard increments the logical depth inside the body"
    (let ((cl-cc/runtime::*rt-call-stack-depth* 0))
      (cl-cc/runtime::rt-with-call-stack-guard ()
        (expect cl-cc/runtime::*rt-call-stack-depth* :to-be 1))
      ;; depth is restored on exit
      (expect cl-cc/runtime::*rt-call-stack-depth* :to-be 0)))

  (it "nested guards eventually trip the overflow condition"
    (let ((cl-cc/runtime::*max-call-stack-depth* 4)
          (cl-cc/runtime::*rt-call-stack-depth* 0))
      (labels ((recurse () (cl-cc/runtime::rt-with-call-stack-guard () (recurse))))
        (expect (handler-case (progn (recurse) nil)
                  (cl-cc/runtime::rt-stack-overflow () t))
                :to-be-truthy)))))

(describe "out-of-memory signalling (runtime-stack.lisp)"
  (it "rt-signal-oom raises rt-oom-condition carrying the supplied words"
    (expect (handler-case (cl-cc/runtime::rt-signal-oom 100 :limit-words 1000 :used-words 500)
              (cl-cc/runtime::rt-oom-condition (c)
                (list (cl-cc/runtime::rt-oom-requested-words c)
                      (cl-cc/runtime::rt-oom-limit-words c)
                      (cl-cc/runtime::rt-oom-used-words c))))
            :to-equal '(100 1000 500)))

  (it "rt-signal-oom derives limit and used words from a heap"
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

(describe "segmented native stack"
  (it "maps 8KB and grows only when the downward stack pointer crosses its limit"
    (let ((cl-cc/runtime::*stack-segment-pool* nil))
      (let* ((root (cl-cc/runtime::stack-segment-note-frame nil 8192))
             (next (cl-cc/runtime::stack-segment-note-frame root 64)))
        (expect (cl-cc/runtime::stack-segment-size root) :to-be 8192)
        (expect (> (cl-cc/runtime::stack-segment-base root) 0) :to-be-truthy)
        (expect (cl-cc/runtime::stack-segment-prev next) :to-be root)
        (expect (cl-cc/runtime::stack-segment-release-frame next 64) :to-be root)
        (expect (cl-cc/runtime::stack-segment-used next) :to-be 0)
        (expect (cl-cc/runtime::stack-segment-next next) :to-be-null))))
  (it "maps an oversize frame safely and resets pooled linkage"
    (let ((cl-cc/runtime::*stack-segment-pool* nil))
      (let* ((root (cl-cc/runtime::stack-segment-note-frame nil 64))
             (large (cl-cc/runtime::stack-segment-note-frame root 9000)))
        (expect (>= (cl-cc/runtime::stack-segment-size large) 9000) :to-be-truthy)
        (cl-cc/runtime::stack-segment-release-frame large 9000)
        (let ((reused (cl-cc/runtime::stack-segment-note-frame root 64)))
          (expect reused :to-be large)
          (expect (cl-cc/runtime::stack-segment-prev reused) :to-be root)
          (expect (cl-cc/runtime::stack-segment-next reused) :to-be-null)
          (expect (cl-cc/runtime::stack-segment-used reused) :to-be 64)))))
  (it "snapshots metadata and restores independently owned chains"
    (let ((cl-cc/runtime::*stack-segment-pool* nil))
      (expect (cl-cc/runtime::stack-segment-snapshot nil) :to-equal nil)
      (expect (cl-cc/runtime::stack-segment-restore nil) :to-be-null)
      (let* ((root (cl-cc/runtime::stack-segment-note-frame nil 128))
             (current (cl-cc/runtime::stack-segment-note-frame root 9000))
             (snapshot (cl-cc/runtime::stack-segment-snapshot current))
             (first (cl-cc/runtime::stack-segment-restore snapshot))
             (second (cl-cc/runtime::stack-segment-restore snapshot)))
        (expect (cl-cc/runtime::stack-segment-snapshot first) :to-equal snapshot)
        (expect (cl-cc/runtime::stack-segment-snapshot second) :to-equal snapshot)
        (expect first :not :to-be second)
        (expect (cl-cc/runtime::stack-segment-prev first)
                :not :to-be
                (cl-cc/runtime::stack-segment-prev second))
        (setf (cl-cc/runtime::stack-segment-used first) 1)
        (expect (cl-cc/runtime::stack-segment-snapshot second) :to-equal snapshot)
        (expect (cl-cc/runtime::release-stack-segment-chain first) :to-be-null)
        (expect (cl-cc/runtime::stack-segment-prev first) :to-be-null)
        (expect (cl-cc/runtime::stack-segment-used first) :to-be 0)
        (cl-cc/runtime::release-stack-segment-chain second)
        (cl-cc/runtime::release-stack-segment-chain current))))
  (it "cleans a partially restored chain when snapshot validation fails"
    (let ((cl-cc/runtime::*stack-segment-pool* nil))
      (assert-signals error
        (cl-cc/runtime::stack-segment-restore '((8192 32) (16 17))))
      (expect (length cl-cc/runtime::*stack-segment-pool*) :to-be 1)
      (let ((released (first cl-cc/runtime::*stack-segment-pool*)))
        (expect (cl-cc/runtime::stack-segment-prev released) :to-be-null)
        (expect (cl-cc/runtime::stack-segment-next released) :to-be-null)
        (expect (cl-cc/runtime::stack-segment-used released) :to-be 0)))))
