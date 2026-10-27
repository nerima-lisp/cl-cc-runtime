;;;; t/os-test.lisp — Coverage for src/os.lisp: OS/thread/signal FR tests
(in-package :cl-cc/runtime/os/test)

;; rt-shell forks; forking while parallel test workers hold heap/malloc
;; locks deadlocks the child before exec on macOS. Run it serially.
(it-sequential
  "FR-1007: rt-shell returns captured stdout."
  (expect (cl-cc/runtime/os:rt-shell "printf hello") :to-equal "hello"))

(it-sequential
  "rt-setenv/rt-getenv/rt-unsetenv round-trip a value through the real process environment."
  (let ((name "RT_OS_TEST_ROUNDTRIP_VAR"))
    (unwind-protect
        (progn
          (expect (cl-cc/runtime/os:rt-getenv name) :to-be nil)
          (cl-cc/runtime/os:rt-setenv name "first" :overwrite t)
          (expect (cl-cc/runtime/os:rt-getenv name) :to-equal "first")
          (cl-cc/runtime/os:rt-setenv name "second" :overwrite t)
          (expect (cl-cc/runtime/os:rt-getenv name) :to-equal "second")
          (cl-cc/runtime/os:rt-unsetenv name)
          (expect (cl-cc/runtime/os:rt-getenv name) :to-be nil))
      (cl-cc/runtime/os:rt-unsetenv name))))

(it-sequential-each
  (("empty" "")
   ("equals-sign" "HAS=EQUALS")
   ("nul-byte" #.(coerce (list #\N #\U #\L #\Null) 'string)))
  "rt-getenv/rt-setenv/rt-unsetenv reject an invalid environment variable name (~A)"
  (label name)
  (declare (ignore label))
  (signals error (cl-cc/runtime/os:rt-getenv name))
  (signals error (cl-cc/runtime/os:rt-setenv name "x"))
  (signals error (cl-cc/runtime/os:rt-unsetenv name)))

(it-sequential
  "FR-1115: stack map delta compression round-trips and safepoint API registers maps."
  (let* ((slots '((8 . :object) (24 . :fixnum) (32 . :object)))
         (compressed (cl-cc/runtime/memory:rt-compress-stackmap-slots slots)))
    (expect
      (cl-cc/runtime/memory:rt-decompress-stackmap-slots compressed)
      :to-equal
      slots)
    (expect
      (search ".gc_map" (cl-cc/runtime/memory:rt-gc-map-section-documentation))
      :to-be-truthy)
    (cl-cc/runtime/memory:rt-emit-gc-safepoint
      :kind
      :test
      :frame-id
      :rt-test-frame
      :live-slots
      slots)
    (expect
      (gethash :rt-test-frame *rt-gc-stackmap-table*)
      :to-be-truthy)))

(it-sequential "fr-624-topology-core-detection"
  (let* ((cl-cc/runtime/os::*rt-detected-cpu-cores*
           (or cl-cc/runtime/os::*rt-detected-cpu-cores* 1))
         (cores (cl-cc/runtime/os:detect-cpu-cores)))
    (expect (integerp cores) :to-be-truthy)
    (expect (plusp cores) :to-be-truthy)))

(it-sequential "fr-624-topology-numa-info-returns-plist"
  (let* ((cl-cc/runtime/os::*rt-detected-cpu-cores*
           (or cl-cc/runtime/os::*rt-detected-cpu-cores* 1))
         (topo (cl-cc/runtime/os:detect-numa-topology)))
    (expect (listp topo) :to-be-truthy)
    (dolist (node topo)
      (expect (listp node) :to-be-truthy)
      (expect (getf node :node-id) :to-be-truthy))))

(it-sequential "fr-624-topology-cpulist-parser-normalizes-ranges"
  (expect (cl-cc/runtime/os::%rt-parse-cpulist "0-2,2,4,nope,6-5,7") :to-equal '(0 1 2 4 7)))

(it-sequential "fr-624-topology-memory-bytes-sums-known-nodes"
  (expect (cl-cc/runtime/os::%rt-topology-memory-bytes
                 '((:node-id 0 :memory-bytes 128)
                   (:node-id 1 :memory-bytes nil)
                   (:node-id 2 :memory-bytes 256))) :to-equal 384))

(it-sequential "fr-624-topology-cache-returns-fresh-tree"
  (let ((cl-cc/runtime/os::*rt-detected-numa-topology*
          '((:node-id 0 :cpus (0 1) :memory-bytes 128 :kind :dram))))
    (let ((topology (cl-cc/runtime/os:detect-numa-topology)))
      (setf (first (getf (first topology) :cpus)) 99))
    (expect (getf (first (cl-cc/runtime/os:detect-numa-topology)) :cpus) :to-equal '(0 1))))
