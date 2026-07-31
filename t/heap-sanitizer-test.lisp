(in-package :cl-cc-runtime/test)

(it-sequential
  "UBSan mode rejects non-integer heap indices for rt-heap-ref."
  (let ((heap (cl-cc/runtime::make-rt-heap)))
    (let ((cl-cc/runtime::*rt-ubsan-enabled* t))
      (signals error (cl-cc/runtime::rt-heap-ref heap :bad-index)))))

(it-sequential
  "UBSan mode rejects negative heap indices for rt-heap-set."
  (let ((heap (cl-cc/runtime::make-rt-heap)))
    (let ((cl-cc/runtime::*rt-ubsan-enabled* t))
      (signals error (cl-cc/runtime::rt-heap-set heap -1 42)))))

(progn
  (it-sequential
    "Heap access keeps working for valid indices when UBSan mode is disabled."
    (let ((heap (cl-cc/runtime::make-rt-heap)))
      (let ((cl-cc/runtime::*rt-ubsan-enabled* nil))
        (cl-cc/runtime::rt-heap-set heap 0 123)
        (expect (cl-cc/runtime::rt-heap-ref heap 0) :to-equal 123))))
  (it-sequential
    "TSan flags a read from one thread-id context of a write left dirty by another, with no happens-before edge between them."
    (let ((heap (cl-cc/runtime::make-rt-heap))
          (cl-cc/runtime::*rt-tsan-enabled* t))
      (cl-cc/runtime::rt-sanitizer-reset-state)
      (let ((cl-cc/runtime::*rt-tsan-thread-id* 1))
        (cl-cc/runtime::rt-heap-set heap 0 10))
      (let ((cl-cc/runtime::*rt-tsan-thread-id* 2))
        (signals error (cl-cc/runtime::rt-heap-ref heap 0)))))
  (it-sequential
    "TSan flags a write from one thread-id context racing a write left dirty by another, with no happens-before edge between them."
    (let ((heap (cl-cc/runtime::make-rt-heap))
          (cl-cc/runtime::*rt-tsan-enabled* t))
      (cl-cc/runtime::rt-sanitizer-reset-state)
      (let ((cl-cc/runtime::*rt-tsan-thread-id* 1))
        (cl-cc/runtime::rt-heap-set heap 0 10))
      (let ((cl-cc/runtime::*rt-tsan-thread-id* 2))
        (signals error (cl-cc/runtime::rt-heap-set heap 0 20)))))
  (it-sequential
    "TSan does not flag reads from two thread-id contexts of a write that happened before the state reset."
    (let ((heap (cl-cc/runtime::make-rt-heap)))
      (cl-cc/runtime::rt-heap-set heap 0 10)
      (let ((cl-cc/runtime::*rt-tsan-enabled* t))
        (cl-cc/runtime::rt-sanitizer-reset-state)
        (let ((cl-cc/runtime::*rt-tsan-thread-id* 1))
          (expect (cl-cc/runtime::rt-heap-ref heap 0) :to-equal 10))
        (let ((cl-cc/runtime::*rt-tsan-thread-id* 2))
          (expect (cl-cc/runtime::rt-heap-ref heap 0) :to-equal 10)))))
  (it-sequential
    "TSan does not flag heap access synchronized across real OS threads by a mutex."
    (let ((heap (cl-cc/runtime::make-rt-heap))
          (mutex (cl-cc/runtime::rt-make-mutex))
          (cl-cc/runtime::*rt-tsan-enabled* t))
      (cl-cc/runtime::rt-sanitizer-reset-state)
      (sb-thread:join-thread
        (sb-thread:make-thread
          (lambda ()
            (cl-cc/runtime::rt-with-mutex (mutex) (cl-cc/runtime::rt-heap-set heap 0 77)))))
      (let ((value nil))
        (sb-thread:join-thread
          (sb-thread:make-thread
            (lambda ()
              (cl-cc/runtime::rt-with-mutex
                (mutex)
                (setf value (cl-cc/runtime::rt-heap-ref heap 0))))))
        (expect value :to-equal 77))))
  (it-sequential
    "%rt-tsan-current-thread-id returns different ids for the main thread and a spawned worker thread."
    (let ((cl-cc/runtime::*rt-tsan-enabled* t))
      (cl-cc/runtime::rt-sanitizer-reset-state)
      (let ((main-id
            (cl-cc/runtime::%rt-with-sanitizer-map-lock
              ()
              (cl-cc/runtime::%rt-tsan-current-thread-id)))
            (worker-id nil))
        (expect
          (cl-cc/runtime::%rt-with-sanitizer-map-lock
            ()
            (cl-cc/runtime::%rt-tsan-current-thread-id))
          :to-equal
          main-id)
        (sb-thread:join-thread
          (sb-thread:make-thread
            (lambda ()
              (setf worker-id (cl-cc/runtime::%rt-with-sanitizer-map-lock
                  ()
                  (cl-cc/runtime::%rt-tsan-current-thread-id))))))
        (expect (= main-id worker-id) :to-be-falsy)))))
