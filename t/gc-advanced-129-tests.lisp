;;;; t/gc-advanced-129-tests.lisp — colored pointers, SATB barrier, region GC,
;;;; epsilon GC (src/gc-advanced-129.lisp).
(in-package :cl-cc-runtime/test)

(describe "epsilon (no-op) GC (gc-advanced-129.lisp)"
  (it "enable-epsilon-gc flips the mode flag"
    (let ((cl-cc/runtime::*gc-epsilon-enabled* nil))
      (expect (cl-cc/runtime::epsilon-gc-enabled-p) :to-be-null)
      (cl-cc/runtime::enable-epsilon-gc)
      (expect (cl-cc/runtime::epsilon-gc-enabled-p) :to-be-truthy))))

(describe "colored pointers (gc-advanced-129.lisp)"
  (it "colour constants are the documented tri-colour bits"
    (expect cl-cc/runtime::+color-marked+ :to-be 1)
    (expect cl-cc/runtime::+color-remapped+ :to-be 2)
    (expect cl-cc/runtime::+color-finalizable+ :to-be 4)
    (expect cl-cc/runtime::+colored-pointer-tag-bits+ :to-be 18))

  (it "set-pointer-color then pointer-color round-trips every 3-bit colour"
    (dotimes (c 8)
      (expect (cl-cc/runtime::pointer-color (cl-cc/runtime::set-pointer-color 0 c))
              :to-be c)))

  (it "strip-pointer-color recovers the raw address"
    (let ((addr #x0000123456789abc))          ; below the 46-bit tag boundary
      (expect (cl-cc/runtime::strip-pointer-color
               (cl-cc/runtime::set-pointer-color addr cl-cc/runtime::+color-marked+))
              :to-be addr)))

  (it "a raw sub-tag address is not a colored pointer"
    (expect (cl-cc/runtime::colored-pointer-p #x1000) :to-be-null))

  (it "a coloured pointer is recognised as colored"
    (expect (cl-cc/runtime::colored-pointer-p
             (cl-cc/runtime::set-pointer-color #x1000 cl-cc/runtime::+color-marked+))
            :to-be-truthy))

  (it "zero colour leaves the pointer uncoloured"
    (expect (cl-cc/runtime::colored-pointer-p (cl-cc/runtime::set-pointer-color 0 0))
            :to-be-null))

  (it-property "colour and address survive a set/strip/extract round-trip"
      ((addr (gen-integer :min 0 :max #x3fffffffffff))   ; 46-bit raw address space
       (color (gen-integer :min 0 :max 7)))
    (let ((tagged (cl-cc/runtime::set-pointer-color addr color)))
      (expect (cl-cc/runtime::pointer-color tagged) :to-be color)
      (expect (cl-cc/runtime::strip-pointer-color tagged) :to-be addr))))

(describe "SATB write barrier (gc-advanced-129.lisp)"
  (it "buffers non-nil old values and drains them in order, then empties the queue"
    (setf (fill-pointer cl-cc/runtime::*satb-queue*) 0)
    (cl-cc/runtime::satb-write-barrier nil :a)
    (cl-cc/runtime::satb-write-barrier nil :b)
    (cl-cc/runtime::satb-write-barrier nil nil) ; nil old-value is ignored
    (let ((seen nil))
      (cl-cc/runtime::satb-drain-queue (lambda (v) (push v seen)))
      (expect (nreverse seen) :to-equal '(:a :b))
      (expect (fill-pointer cl-cc/runtime::*satb-queue*) :to-be 0)))

  (it "draining an empty queue calls the mark function zero times"
    (setf (fill-pointer cl-cc/runtime::*satb-queue*) 0)
    (let ((calls 0))
      (cl-cc/runtime::satb-drain-queue (lambda (v) (declare (ignore v)) (incf calls)))
      (expect calls :to-be 0))))

(describe "region-based GC (gc-advanced-129.lisp)"
  (it "a fresh region defaults to the eden generation with zero live bytes"
    (let ((r (cl-cc/runtime::make-gc-region)))
      (expect (cl-cc/runtime::gc-region-generation r) :to-be :eden)
      (expect (cl-cc/runtime::gc-region-live-bytes r) :to-be 0)))

  (it "an empty region has a garbage ratio of 1.0"
    (let ((r (cl-cc/runtime::make-gc-region :live-bytes 0)))
      (expect (cl-cc/runtime::estimate-region-garbage-ratio r) :to-equal 1.0)))

  (it "a fully live region has a garbage ratio of 0.0"
    (let ((r (cl-cc/runtime::make-gc-region :live-bytes cl-cc/runtime::+gc-region-size+)))
      (expect (cl-cc/runtime::estimate-region-garbage-ratio r) :to-equal 0.0)))

  (it "a half-live region has a garbage ratio of 0.5"
    (let ((r (cl-cc/runtime::make-gc-region
              :live-bytes (floor cl-cc/runtime::+gc-region-size+ 2))))
      (expect (cl-cc/runtime::estimate-region-garbage-ratio r) :to-equal 0.5)))

  (it "estimate-region-garbage-ratio stores the computed ratio on the region"
    (let ((r (cl-cc/runtime::make-gc-region :live-bytes 0)))
      (cl-cc/runtime::estimate-region-garbage-ratio r)
      (expect (cl-cc/runtime::gc-region-garbage-ratio r) :to-equal 1.0))))
