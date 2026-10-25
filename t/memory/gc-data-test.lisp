;;;; t/gc-data-test.lisp — GC data declarations: stackmap struct, tunable
;;;; parameters, and the *compacting-gc-enabled* symbol-macro (src/gc-data.lisp).
(in-package :cl-cc/runtime/memory/test)

(describe
  "rt-stackmap (gc-data.lisp)"
  (it
    "the constructor defaults slots to nil and source to :compiler-stub"
    (let ((sm (cl-cc/runtime/memory:make-rt-stackmap :frame-id 42)))
      (expect (rt-stackmap-p sm) :to-be-truthy)
      (expect (rt-stackmap-frame-id sm) :to-be 42)
      (expect (cl-cc/runtime/memory:rt-stackmap-slots sm) :to-be-null)
      (expect (rt-stackmap-source sm) :to-be :compiler-stub)))
  (it
    "accepts an explicit slot alist and source"
    (let ((sm
          (cl-cc/runtime/memory:make-rt-stackmap
            :frame-id
            1
            :slots
            '((0 . :object) (8 . :fixnum))
            :source
            :compiler)))
      (expect
        (cl-cc/runtime/memory:rt-stackmap-slots sm)
        :to-equal
        '((0 . :object) (8 . :fixnum)))
      (expect (rt-stackmap-source sm) :to-be :compiler))))

(describe
  "GC tunable parameters (gc-data.lisp)"
  (it
    "the VM call-frame pool limit defaults to 256"
    (expect *vm-call-frame-pool-limit* :to-be 256))
  (it
    "the GC worker count defaults to sequential (0)"
    (expect cl-cc/runtime/memory:*gc-worker-count* :to-be 0))
  (it
    "verification and stress modes default off"
    (expect cl-cc/runtime/memory:*gc-verify-after-collect* :to-be-null)
    (expect cl-cc/runtime/memory:*gc-stress-mode* :to-be-null))
  (it
    "periodic compaction is disabled by default"
    (expect cl-cc/runtime/memory:*gc-compact-after-major-cycles* :to-be 0))
  (it
    "the default GC thread set describes a single :main thread"
    (expect (getf (first cl-cc/runtime/memory:*gc-threads*) :name) :to-be :main)))

(describe
  "*compacting-gc-enabled* symbol-macro (gc-data.lisp)"
  (it
    "reads through to *gc-compaction-enabled*"
    (let ((*gc-compaction-enabled* nil))
      (expect cl-cc/runtime/memory:*compacting-gc-enabled* :to-be-null)))
  (it
    "writes through to *gc-compaction-enabled*"
    (let ((*gc-compaction-enabled* nil))
      (setf cl-cc/runtime/memory:*compacting-gc-enabled* t)
      (expect *gc-compaction-enabled* :to-be-truthy))))
