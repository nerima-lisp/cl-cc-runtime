;;;; t/os-test.lisp — Coverage for src/os.lisp: OS/thread/signal FR tests
(in-package :cl-cc-runtime/test)

;; rt-shell forks; forking while parallel test workers hold heap/malloc
;; locks deadlocks the child before exec on macOS. Run it serially.
(it-sequential
  "FR-1007: rt-shell returns captured stdout."
  (expect (cl-cc/runtime::rt-shell "printf hello") :to-equal "hello"))

(it-sequential
  "rt-setenv/rt-getenv/rt-unsetenv round-trip a value through the real process environment."
  (let ((name "RT_OS_TEST_ROUNDTRIP_VAR"))
    (unwind-protect
        (progn
          (expect (cl-cc/runtime:rt-getenv name) :to-be nil)
          (cl-cc/runtime:rt-setenv name "first" :overwrite t)
          (expect (cl-cc/runtime:rt-getenv name) :to-equal "first")
          (cl-cc/runtime:rt-setenv name "second" :overwrite t)
          (expect (cl-cc/runtime:rt-getenv name) :to-equal "second")
          (cl-cc/runtime:rt-unsetenv name)
          (expect (cl-cc/runtime:rt-getenv name) :to-be nil))
      (cl-cc/runtime:rt-unsetenv name))))

(it-sequential-each
  (("empty" "")
   ("equals-sign" "HAS=EQUALS")
   ("nul-byte" #.(coerce (list #\N #\U #\L #\Null) 'string)))
  "rt-getenv/rt-setenv/rt-unsetenv reject an invalid environment variable name (~A)"
  (label name)
  (declare (ignore label))
  (signals error (cl-cc/runtime:rt-getenv name))
  (signals error (cl-cc/runtime:rt-setenv name "x"))
  (signals error (cl-cc/runtime:rt-unsetenv name)))

(it-sequential
  "FR-1115: stack map delta compression round-trips and safepoint API registers maps."
  (let* ((slots '((8 . :object) (24 . :fixnum) (32 . :object)))
         (compressed (cl-cc/runtime::rt-compress-stackmap-slots slots)))
    (expect
      (cl-cc/runtime::rt-decompress-stackmap-slots compressed)
      :to-equal
      slots)
    (expect
      (search ".gc_map" (cl-cc/runtime::rt-gc-map-section-documentation))
      :to-be-truthy)
    (cl-cc/runtime::rt-emit-gc-safepoint
      :kind
      :test
      :frame-id
      :rt-test-frame
      :live-slots
      slots)
    (expect
      (gethash :rt-test-frame cl-cc/runtime::*rt-gc-stackmap-table*)
      :to-be-truthy)))
