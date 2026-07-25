;;;; t/gc-data-tests.lisp — GC data declarations: stackmap struct, tunable
;;;; parameters, and the *compacting-gc-enabled* symbol-macro (src/gc-data.lisp).
(in-package :cl-cc-runtime/test)

(describe "rt-stackmap (gc-data.lisp)"
  (it "the constructor defaults slots to nil and source to :compiler-stub"
    (let ((sm (cl-cc/runtime::make-rt-stackmap :frame-id 42)))
      (expect (cl-cc/runtime::rt-stackmap-p sm) :to-be-truthy)
      (expect (cl-cc/runtime::rt-stackmap-frame-id sm) :to-be 42)
      (expect (cl-cc/runtime::rt-stackmap-slots sm) :to-be-null)
      (expect (cl-cc/runtime::rt-stackmap-source sm) :to-be :compiler-stub)))

  (it "accepts an explicit slot alist and source"
    (let ((sm (cl-cc/runtime::make-rt-stackmap
               :frame-id 1 :slots '((0 . :object) (8 . :fixnum)) :source :compiler)))
      (expect (cl-cc/runtime::rt-stackmap-slots sm) :to-equal '((0 . :object) (8 . :fixnum)))
      (expect (cl-cc/runtime::rt-stackmap-source sm) :to-be :compiler))))

(describe "GC tunable parameters (gc-data.lisp)"
  (it "the VM call-frame pool limit defaults to 256"
    (expect cl-cc/runtime::*vm-call-frame-pool-limit* :to-be 256))

  (it "the GC worker count defaults to sequential (0)"
    (expect cl-cc/runtime::*gc-worker-count* :to-be 0))

  (it "verification and stress modes default off"
    (expect cl-cc/runtime::*gc-verify-after-collect* :to-be-null)
    (expect cl-cc/runtime::*gc-stress-mode* :to-be-null))

  (it "periodic compaction is disabled by default"
    (expect cl-cc/runtime::*gc-compact-after-major-cycles* :to-be 0))

  (it "the default GC thread set describes a single :main thread"
    (expect (getf (first cl-cc/runtime::*gc-threads*) :name) :to-be :main)))

(describe "*compacting-gc-enabled* symbol-macro (gc-data.lisp)"
  (it "reads through to *gc-compaction-enabled*"
    (let ((cl-cc/runtime::*gc-compaction-enabled* nil))
      (expect cl-cc/runtime::*compacting-gc-enabled* :to-be-null)))

  (it "writes through to *gc-compaction-enabled*"
    (let ((cl-cc/runtime::*gc-compaction-enabled* nil))
      (setf cl-cc/runtime::*compacting-gc-enabled* t)
      (expect cl-cc/runtime::*gc-compaction-enabled* :to-be-truthy))))
