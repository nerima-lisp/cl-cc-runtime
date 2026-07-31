;;;; t/heap-trace-test.lisp — Card Table + Address Predicate Tests
;;;
;;; Tests for src/runtime/heap-trace.lisp:
;;;   - Card table helpers: rt-card-index, rt-card-dirty-p,
;;;     rt-card-mark-dirty, rt-card-clear, rt-card-clear-all
;;;   - Address predicates: rt-young-addr-p, rt-old-addr-p, rt-heap-addr-p
;;;   - Pointer slot resolver: rt-object-pointer-slots
(in-package :cl-cc-runtime/test)

;;; ------------------------------------------------------------
;;; Suite
;;; ------------------------------------------------------------
;;; ------------------------------------------------------------
;;; Helpers
;;; ------------------------------------------------------------
(defun %make-trace-heap ()
  "Create a minimal heap for tracing tests.
   young-size=32 → semi-size=16, young-from-base=0, young addresses 0..15.
   old-size=32  → old-base=32, old addresses 32..63, num-cards=ceiling(32/64)=1.
   large-obj-size=old-size → large-obj addresses 64..95."
  (cl-cc/runtime::make-rt-heap :young-size 32 :old-size 32))

(defun %write-obj-header (heap addr size tag)
  "Write an object header at ADDR with SIZE words and TYPE-TAG."
  (cl-cc/runtime::rt-heap-set-header
    heap
    addr
    (cl-cc/runtime::make-rt-header size tag :gc-bits 0)))

;;; ------------------------------------------------------------
;;; Card Table: rt-card-index
;;; ------------------------------------------------------------
(it-sequential
  "rt-card-index at old-base address returns 0."
  (let* ((heap (%make-trace-heap))
         (old-base (cl-cc/runtime::rt-heap-old-base heap)))
    (expect (cl-cc/runtime::rt-card-index heap old-base) :to-equal 0)))

(it-sequential
  "rt-card-index 10 bytes past old-base returns 0 (same card, card-size=64)."
  (let* ((heap (%make-trace-heap))
         (old-base (cl-cc/runtime::rt-heap-old-base heap)))
    (expect (cl-cc/runtime::rt-card-index heap (+ old-base 10)) :to-equal 0)))

;;; ------------------------------------------------------------
;;; Card Table: mark / clear / dirty-p
;;; ------------------------------------------------------------
(it-sequential
  "Card starts clean; mark-dirty makes dirty-p true; clear reverts it; clear-all clears all."
  (let* ((heap (%make-trace-heap))
         (old-base (cl-cc/runtime::rt-heap-old-base heap)))
    (expect (cl-cc/runtime::rt-card-dirty-p heap old-base) :to-be-falsy)
    (cl-cc/runtime::rt-card-mark-dirty heap old-base)
    (expect (cl-cc/runtime::rt-card-dirty-p heap old-base) :to-be-truthy)
    (cl-cc/runtime::rt-card-clear heap old-base)
    (expect (cl-cc/runtime::rt-card-dirty-p heap old-base) :to-be-falsy)
    (cl-cc/runtime::rt-card-mark-dirty heap old-base)
    (cl-cc/runtime::rt-card-clear-all heap)
    (expect (cl-cc/runtime::rt-card-dirty-p heap old-base) :to-be-falsy)))

;;; ------------------------------------------------------------
;;; Address Predicates
;;; ------------------------------------------------------------
(it-sequential-each (("in-range-0"  0  t)
                      ("in-range-10" 10 t)
                      ("in-range-15" 15 t)
                      ("boundary-16" 16 nil)
                      ("old-base-32" 32 nil)
                      ("negative"    -1 nil))
    "rt-young-addr-p returns true iff addr is within young from-space [0, 16) (~A)."
    (label addr expected)
  (declare (ignore label))
  (let ((heap (%make-trace-heap)))
    (expect
      (not (not (cl-cc/runtime::rt-young-addr-p heap addr)))
      :to-equal
      expected)))

(it-sequential-each (("below-old-31" 31 nil)
                      ("old-base-32" 32 t)
                      ("old-mid-40"  40 t)
                      ("old-end-63"  63 t)
                      ("beyond-64"   64 nil)
                      ("young-0"      0 nil))
    "rt-old-addr-p returns true iff addr is within old-space [32, 64) (~A)."
    (label addr expected)
  (declare (ignore label))
  (let ((heap (%make-trace-heap)))
    (expect (not (not (cl-cc/runtime::rt-old-addr-p heap addr))) :to-equal expected)))

(it-sequential-each (("young-0"      0  t)
                      ("young-15"     15 t)
                      ("gap-16"       16 nil)
                      ("gap-31"       31 nil)
                      ("old-32"       32 t)
                      ("old-63"       63 t)
                      ("large-obj-64" 64 t)
                      ("large-obj-95" 95 t)
                      ("beyond-96"    96 nil))
    "rt-heap-addr-p is the union of young, old, and large-obj: true for 0..15, 32..63, and 64..95 (~A)."
    (label addr expected)
  (declare (ignore label))
  (let ((heap (%make-trace-heap)))
    (expect
      (not (not (cl-cc/runtime::rt-heap-addr-p heap addr)))
      :to-equal
      expected)))

;;; ------------------------------------------------------------
;;; rt-object-pointer-slots
;;; ------------------------------------------------------------
(it-sequential
  "Cons (size=3, tag=1): pointer slots are (1 2) — car and cdr."
  (let ((heap (%make-trace-heap)))
    (%write-obj-header heap 0 3 1)
    (expect (cl-cc/runtime::rt-object-pointer-slots heap 0) :to-equal '(1 2))))

(it-sequential
  "Symbol (size=4, tag=2): pointer slots are (1 2 3) — name, pkg, value."
  (let ((heap (%make-trace-heap)))
    (%write-obj-header heap 0 4 2)
    (expect (cl-cc/runtime::rt-object-pointer-slots heap 0) :to-equal '(1 2 3))))

(it-sequential
  "Closure-4 (size=4, tag=3): pointer slots are (2 3) — env and code."
  (let ((heap (%make-trace-heap)))
    (%write-obj-header heap 0 4 3)
    (expect (cl-cc/runtime::rt-object-pointer-slots heap 0) :to-equal '(2 3))))

(it-sequential
  "Closure-2 (size=2, tag=3): pointer slots are () — no pointer fields."
  (let ((heap (%make-trace-heap)))
    (%write-obj-header heap 0 2 3)
    (expect (cl-cc/runtime::rt-object-pointer-slots heap 0) :to-equal '())))

(it-sequential
  "Array-4 (size=4, tag=5): pointer slots are (2 3) — elements."
  (let ((heap (%make-trace-heap)))
    (%write-obj-header heap 0 4 5)
    (expect (cl-cc/runtime::rt-object-pointer-slots heap 0) :to-equal '(2 3))))

(it-sequential
  "Other-3 (size=3, tag=7): pointer slots are (1 2)."
  (let ((heap (%make-trace-heap)))
    (%write-obj-header heap 0 3 7)
    (expect (cl-cc/runtime::rt-object-pointer-slots heap 0) :to-equal '(1 2))))

(it-sequential
  "String (size=5, tag=6): rt-object-pointer-slots returns nil."
  (let ((heap (%make-trace-heap)))
    (%write-obj-header heap 0 5 6)
    (expect (cl-cc/runtime::rt-object-pointer-slots heap 0) :to-equal nil)))

(it-sequential
  "Unknown object (size=2, tag=0): rt-object-pointer-slots returns nil."
  (let ((heap (%make-trace-heap)))
    (%write-obj-header heap 0 2 0)
    (expect (cl-cc/runtime::rt-object-pointer-slots heap 0) :to-equal nil)))
