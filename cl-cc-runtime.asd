;;;; cl-cc-runtime.asd -- the runtime library extracted from the cl-cc monorepo.
;;;;
;;;; Both systems live in this one file. There is no cl-cc-runtime-test.asd:
;;;; a second .asd at the root duplicates the eight metadata fields, and the
;;;; two copies drift.
;;;;
;;;; System names are written as STRINGS rather than #:symbols or :keywords, so
;;;; that reading this file does not depend on the reader's current package,
;;;; and so that a grep for a system name has exactly one form to match. This
;;;; file previously mixed :cl-cc-runtime with "cl-cc-runtime-test".

(in-package #:asdf-user)

(defsystem "cl-cc-runtime"
  :description "cl-cc runtime library: rt-* primitives, GC, heap, frame, value codec, and concurrency"
  :long-description "The target runtime the cl-cc compiler emits against: the
:cl-cc/runtime package system, a generational garbage collector, the heap and
allocator, value representation and codecs, images, FFI, and the lock-free and
wait-free concurrency primitives. It builds on the sibling nerima-lisp kits for
structured logging, process execution and JSON rather than reimplementing them."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "0.1.0"
  :homepage "https://github.com/nerima-lisp/cl-cc-runtime"
  :bug-tracker "https://github.com/nerima-lisp/cl-cc-runtime/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-cc-runtime.git")
  ;; L3 (domain), depth 3 -- the deepest system in the org. The longest path is
  ;; cl-log-kit -> cl-boundary-kit -> cl-process-kit -> cl-cc-runtime, which is
  ;; at the depth ceiling of 4 with one hop to spare. See DEPENDENCY_POLICY.md
  ;; before adding a fourth dependency here.
  :depends-on ("cl-log-kit" "cl-process-kit" "cl-json-kit")
  :pathname "src"
  :serial t
  :components
  ;; src/ is flat and every defpackage lives in src/package.lisp.
  ((:file "package")
   (:file "runtime-region")
   (:file "runtime")
   (:file "runtime-stack")
   (:file "runtime-conditions")
   (:file "runtime-list")
   (:file "runtime-ops")
   (:file "runtime-strings")
   (:file "runtime-math-io")
   (:file "runtime-clos")
   (:file "runtime-clos-dispatch")
   (:file "runtime-io")
   (:file "runtime-packages")
   (:file "runtime-pathnames")
   (:file "value")
   (:file "value-codec")
   (:file "frame")
   (:file "heap-data")
   (:file "heap-core")
   (:file "heap-sanitizer")
   (:file "heap-layout")
   (:file "heap-access")
   (:file "heap-free-list")
   (:file "heap-resize")
   (:file "heap-trace")
   (:file "gc-references")
   (:file "gc-profile")
   (:file "gc-data")
   (:file "gc-safepoints")
   (:file "gc-policy")
   (:file "gc-roots-objects")
   (:file "gc-tlab")
   (:file "gc-minor")
   (:file "gc-write-barrier")
   (:file "gc-finalizers")
   (:file "gc-major-mark")
   (:file "gc-workers")
   (:file "gc-major-sweep")
   (:file "gc-sweep-telemetry")
   ;; Synchronization & concurrency primitives
   (:file "deadlock")
   (:file "sync")
   (:file "portable")
   (:file "lockfree")
   (:file "spsc")
   (:file "ebr")
   (:file "hazard")
   (:file "rcu")
   (:file "qsbr")
   (:file "scheduler")
   (:file "future")
   (:file "channel")
   (:file "actor")
   (:file "task")
   (:file "stm")
   (:file "async")
   (:file "async-generators")
   (:file "effects")
   (:file "fiber")
   (:file "context")
   (:file "image")
   (:file "image-core")
   (:file "image-restore")
   ;; OS / I/O / Network
   (:file "os")
   (:file "signals")
   (:file "mmap")
   (:file "heap-hugepages")
   (:file "heap-los")
   (:file "ffi")
   (:file "xom")
   (:file "net")
   (:file "io-uring")
   (:file "event-loop")
   (:file "zerocopy")
   (:file "ratelimit")
   ;; Debug / Observability / Distributed
   (:file "perf")
   (:file "otel")
   (:file "continuous-profile")
   (:file "log")
   (:file "metrics")
   (:file "consensus")
   (:file "crdt")
   (:file "cluster")
   ;; Memory / Topology / Algorithms
   (:file "allocator")
   (:file "topology")
   (:file "mvcc")
   (:file "hash-weak")
   (:file "parallel-algo")
   ;; GPU / WASM / Reactive / Async
   (:file "gpu")
   (:file "reactive")
   ;; Phase 116-127: Serialization / Crypto / Compression
   (:file "serialize")
   (:file "crypto")
   (:file "compress")
   (:file "gc-advanced-129"))
  :in-order-to ((test-op (test-op "cl-cc-runtime/test"))))

;;; The test system is "cl-cc-runtime/test", not "cl-cc-runtime-test": one
;;; system per feature, named by the slash-separated ASDF convention, so
;;; `(asdf:test-system "cl-cc-runtime")` reaches it through :in-order-to.
(defsystem "cl-cc-runtime/test"
  :description "Test system for cl-cc-runtime."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "0.1.0"
  :homepage "https://github.com/nerima-lisp/cl-cc-runtime"
  :bug-tracker "https://github.com/nerima-lisp/cl-cc-runtime/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-cc-runtime.git")
  ;; cl-weave is the org's only test framework.
  :depends-on ("cl-cc-runtime" "cl-weave")
  :pathname "t"
  :serial t
  :components
  ((:file "package")
   (:file "consensus-tests")
   (:file "crypto-tests")
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
   (:file "crdt-tests")
   (:file "cluster-tests")
   (:file "gpu-tests")
   (:file "metrics-tests")
   (:file "parallel-algo-tests")
   (:file "zerocopy-tests")
   (:file "signals-tests")
   (:file "reactive-tests")
   (:file "perf-tests")
   (:file "lockfree-tests")
   (:file "spsc-tests")
   (:file "hazard-tests")
   (:file "ebr-tests")
   (:file "rcu-tests")
   (:file "qsbr-tests")
   (:file "mvcc-tests")
   (:file "actor-tests")
   (:file "channel-tests")
   (:file "stm-tests")
   (:file "task-tests")
   (:file "future-tests")
   (:file "fiber-tests")
   (:file "scheduler-tests")
   (:file "event-loop-tests")
   (:file "effects-tests")
   (:file "allocator-tests")
   (:file "compress-tests")
   (:file "context-tests")
   (:file "async-generators-tests")
   (:file "runtime-stack-tests")
   (:file "gc-advanced-129-tests")
   (:file "ratelimit-tests")
   (:file "gc-data-tests")
   (:file "frame-tests-2")
   (:file "sync-tests")
   (:file "runtime-ops-tests")
   (:file "runtime-math-io-tests")
   (:file "runtime-pathnames-tests")
   (:file "runtime-conditions-tests")
   (:file "image-tests")
   (:file "async-tests")
   (:file "portable-tests")
   (:file "gc-workers-tests")
   (:file "gc-major-sweep-extra-tests"))
  :perform (test-op (op system)
             (declare (ignore op system))
             (unless (uiop:symbol-call :cl-weave :run-all
                                       :reporter :spec :pass-with-no-tests nil)
               (error "cl-cc-runtime tests failed"))))
