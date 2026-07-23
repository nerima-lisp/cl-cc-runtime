(asdf:defsystem "cl-cc-runtime-test"
  :description "Tests for cl-cc-runtime (cl-weave)."
  :version "0.1.0"
  :author "takeokunn"
  :license "MIT"
  :homepage "https://github.com/nerima-lisp/cl-cc-runtime"
  :depends-on ("cl-cc-runtime" "cl-weave")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "continuous-profile-tests")
               (:file "deadlock-tests")
               (:file "frame-tests")
               (:file "gc-fr-tests")
               (:file "gc-stats-tests")
               (:file "gc-sweep-major-tests")
               (:file "gc-tests")
               (:file "gc-write-barrier-tests")
               (:file "heap-sanitizer-tests")
               (:file "heap-trace-tests")
               (:file "runtime-clos-tests")
               (:file "runtime-io-tests")
               (:file "runtime-serialize-tests")
               (:file "runtime-stdlib-3-image-tests")
               (:file "runtime-stdlib-3-os-tests")
               (:file "runtime-strings-chars-tests")
               (:file "runtime-tests-2")
               (:file "runtime-tests")
               (:file "value-tests")
               )
  :perform (asdf:test-op (op system)
             (declare (ignore op system))
             (unless (uiop:symbol-call :cl-weave :run-all :reporter :spec :pass-with-no-tests nil)
               (error "cl-cc-runtime tests failed"))))
