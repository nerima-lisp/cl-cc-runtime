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
   (:file "runtime-conditions")
   (:file "runtime-code-cache")
   (:file "runtime-stack")
   (:file "runtime-list")
   (:file "runtime-ops")
   (:file "runtime-strings")
   (:file "runtime-weak-hash-table")
   (:file "runtime-dynamic-binding")
   (:file "runtime-math-io")
   (:file "runtime-clos")
   (:file "runtime-clos-dispatch")
   (:file "runtime-clos-applicability")
   (:file "runtime-clos-invoke")
   (:file "runtime-io")
   (:file "runtime-packages")
   (:file "runtime-pathnames")
   (:file "value-tags")
   (:file "value")
   (:file "value-codec")
   (:file "value-pinned-array")
   (:file "frame")
   (:file "heap-data")
   (:file "heap-core")
   (:file "heap-sanitizer")
   (:file "heap-layout")
   (:file "heap-access")
   (:file "heap-forwarding")
   (:file "heap-numa")
   (:file "heap-stats")
   (:file "heap-free-list")
   (:file "heap-resize")
   (:file "heap-trace")
   (:file "gc-references")
   (:file "gc-weak-processing")
   (:file "gc-profile")
   (:file "gc-data")
   (:file "gc-safepoints")
   (:file "gc-policy")
   (:file "gc-pinning")
   (:file "gc-roots-objects")
   (:file "gc-stackmaps")
   (:file "gc-binding-scan")
   (:file "gc-heap-verify")
   (:file "gc-alloc")
   (:file "gc-copy")
   (:file "gc-tlab")
   (:file "gc-minor")
   (:file "gc-write-barrier")
   (:file "gc-finalizers")
   (:file "gc-major-mark")
   (:file "gc-mark-work")
   (:file "gc-workers")
   (:file "gc-major-sweep")
   (:file "gc-compact")
   (:file "gc-concurrent-sweep")
   (:file "gc-major-collect")
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
   (:file "scheduler-work-stealing")
   (:file "scheduler-native-thread")
   (:file "scheduler-thread-pool")
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
   (:file "image-core-graph")
   (:file "image-core-persist")
   (:file "image-restore")
   ;; OS / I/O / Network
   (:file "os")
   (:file "signals")
   (:file "mmap")
   (:file "heap-hugepages")
   (:file "heap-los")
   (:file "ffi")
   (:file "ffi-embedding-api")
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
   (:file "continuous-profile-export")
   (:file "log")
   (:file "metrics")
   (:file "consensus")
   (:file "crdt")
   (:file "cluster")
   ;; Memory / Topology / Algorithms
   (:file "allocator")
   (:file "topology")
   (:file "topology-numa-memory")
   (:file "mvcc")
   (:file "hash-weak")
   (:file "parallel-algo")
   ;; GPU / WASM / Reactive / Async
   (:file "gpu")
   (:file "reactive")
   (:file "reactive-publishers")
   ;; Phase 116-127: Serialization / Crypto / Compression
   (:file "serialize")
   (:file "deserialize")
   (:file "crypto")
   (:file "crypto-base64")
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
   (:file "consensus-test")
   (:file "crypto-test")
   (:file "continuous-profile-test")
   (:file "deadlock-test")
   (:file "frame-test")
   (:file "gc-requirements-test")
   (:file "gc-sweep-telemetry-test")
   (:file "gc-major-sweep-test")
   (:file "gc-minor-test")
   (:file "gc-write-barrier-test")
   (:file "heap-sanitizer-test")
   (:file "heap-trace-test")
   (:file "runtime-clos-test")
   (:file "runtime-io-test")
   (:file "serialize-test")
   (:file "image-core-test")
   (:file "os-test")
   (:file "runtime-strings-chars-test")
   (:file "runtime-data-ops-test")
   (:file "runtime-test")
   (:file "value-test")
   (:file "crdt-test")
   (:file "cluster-test")
   (:file "gpu-test")
   (:file "metrics-test")
   (:file "parallel-algo-test")
   (:file "zerocopy-test")
   (:file "signals-test")
   (:file "reactive-test")
   (:file "perf-test")
   (:file "lockfree-test")
   (:file "spsc-test")
   (:file "hazard-test")
   (:file "ebr-test")
   (:file "rcu-test")
   (:file "qsbr-test")
   (:file "mvcc-test")
   (:file "actor-test")
   (:file "channel-test")
   (:file "stm-test")
   (:file "task-test")
   (:file "future-test")
   (:file "fiber-test")
   (:file "scheduler-test")
   (:file "event-loop-test")
   (:file "effects-test")
   (:file "allocator-test")
   (:file "compress-test")
   (:file "context-test")
   (:file "async-generators-test")
   (:file "runtime-stack-test")
   (:file "mutation-test")
   (:file "gc-advanced-129-test")
   (:file "ratelimit-test")
   (:file "gc-data-test")
   (:file "frame-boundary-test")
   (:file "sync-test")
   (:file "runtime-ops-test")
   (:file "runtime-math-io-test")
   (:file "runtime-pathnames-test")
   (:file "runtime-conditions-test")
   (:file "image-test")
   (:file "async-test")
   (:file "portable-test")
   (:file "gc-workers-test")
   (:file "gc-major-sweep-incremental-test"))
  :perform (test-op (op system)
             (declare (ignore op system))
             (unless (uiop:symbol-call :cl-weave :run-all
                                       :reporter :spec :pass-with-no-tests nil)
               (error "cl-cc-runtime tests failed"))))
