(in-package :cl-cc-runtime/test)

(in-suite cl-cc-unit-suite)

(deftest runtime-ubsan-heap-ref-rejects-non-integer-index
  "UBSan mode rejects non-integer heap indices for rt-heap-ref."
  (let ((heap (cl-cc/runtime::make-rt-heap)))
    (let ((cl-cc/runtime::*rt-ubsan-enabled* t))
      (assert-signals error
        (cl-cc/runtime::rt-heap-ref heap :bad-index)))))

(deftest runtime-ubsan-heap-set-rejects-negative-index
  "UBSan mode rejects negative heap indices for rt-heap-set."
  (let ((heap (cl-cc/runtime::make-rt-heap)))
    (let ((cl-cc/runtime::*rt-ubsan-enabled* t))
      (assert-signals error
        (cl-cc/runtime::rt-heap-set heap -1 42)))))

(progn
  (deftest runtime-ubsan-heap-access-works-when-disabled
    "Heap access keeps working for valid indices when UBSan mode is disabled."
    (let ((heap (cl-cc/runtime::make-rt-heap)))
      (let ((cl-cc/runtime::*rt-ubsan-enabled* nil))
        (cl-cc/runtime::rt-heap-set heap 0 123)
        (assert-= 123 (cl-cc/runtime::rt-heap-ref heap 0)))))

  (deftest runtime-tsan-detects-unsynchronized-read-write
    (let ((heap (cl-cc/runtime::make-rt-heap))
          (cl-cc/runtime::*rt-tsan-enabled* t))
      (cl-cc/runtime::rt-sanitizer-reset-state)
      (let ((cl-cc/runtime::*rt-tsan-thread-id* 1))
        (cl-cc/runtime::rt-heap-set heap 0 10))
      (let ((cl-cc/runtime::*rt-tsan-thread-id* 2))
        (assert-signals error (cl-cc/runtime::rt-heap-ref heap 0)))))

  (deftest runtime-tsan-detects-unsynchronized-write-write
    (let ((heap (cl-cc/runtime::make-rt-heap))
          (cl-cc/runtime::*rt-tsan-enabled* t))
      (cl-cc/runtime::rt-sanitizer-reset-state)
      (let ((cl-cc/runtime::*rt-tsan-thread-id* 1))
        (cl-cc/runtime::rt-heap-set heap 0 10))
      (let ((cl-cc/runtime::*rt-tsan-thread-id* 2))
        (assert-signals error (cl-cc/runtime::rt-heap-set heap 0 20)))))

  (deftest runtime-tsan-allows-concurrent-reads
    (let ((heap (cl-cc/runtime::make-rt-heap)))
      (cl-cc/runtime::rt-heap-set heap 0 10)
      (let ((cl-cc/runtime::*rt-tsan-enabled* t))
        (cl-cc/runtime::rt-sanitizer-reset-state)
        (let ((cl-cc/runtime::*rt-tsan-thread-id* 1))
          (assert-= 10 (cl-cc/runtime::rt-heap-ref heap 0)))
        (let ((cl-cc/runtime::*rt-tsan-thread-id* 2))
          (assert-= 10 (cl-cc/runtime::rt-heap-ref heap 0))))))

  (deftest runtime-tsan-mutex-establishes-happens-before
    (let ((heap (cl-cc/runtime::make-rt-heap))
          (mutex (cl-cc/runtime::rt-make-mutex))
          (cl-cc/runtime::*rt-tsan-enabled* t))
      (cl-cc/runtime::rt-sanitizer-reset-state)
      (sb-thread:join-thread
       (sb-thread:make-thread
        (lambda ()
          (cl-cc/runtime::rt-with-mutex (mutex)
            (cl-cc/runtime::rt-heap-set heap 0 77)))))
      (let ((value nil))
        (sb-thread:join-thread
         (sb-thread:make-thread
          (lambda ()
            (cl-cc/runtime::rt-with-mutex (mutex)
              (setf value (cl-cc/runtime::rt-heap-ref heap 0))))))
        (assert-= 77 value))))

  (deftest runtime-tsan-assigns-stable-distinct-host-thread-ids
    (let ((cl-cc/runtime::*rt-tsan-enabled* t))
      (cl-cc/runtime::rt-sanitizer-reset-state)
      (let ((main-id (cl-cc/runtime::%rt-with-sanitizer-map-lock ()
                       (cl-cc/runtime::%rt-tsan-current-thread-id)))
            (worker-id nil))
        (assert-= main-id
                  (cl-cc/runtime::%rt-with-sanitizer-map-lock ()
                    (cl-cc/runtime::%rt-tsan-current-thread-id)))
        (sb-thread:join-thread
         (sb-thread:make-thread
          (lambda ()
            (setf worker-id
                  (cl-cc/runtime::%rt-with-sanitizer-map-lock ()
                    (cl-cc/runtime::%rt-tsan-current-thread-id))))))
        (assert-false (= main-id worker-id))))))
