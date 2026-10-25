(in-package :cl-cc/runtime/memory/test)

(it-sequential
  "UBSan mode rejects non-integer heap indices for rt-heap-ref."
  (let ((heap (cl-cc/runtime/memory:make-rt-heap)))
    (let ((cl-cc/runtime/memory:*rt-ubsan-enabled* t))
      (signals error (cl-cc/runtime/memory:rt-heap-ref heap :bad-index)))))

(it-sequential
  "UBSan mode rejects negative heap indices for rt-heap-set."
  (let ((heap (cl-cc/runtime/memory:make-rt-heap)))
    (let ((cl-cc/runtime/memory:*rt-ubsan-enabled* t))
      (signals error (cl-cc/runtime/memory:rt-heap-set heap -1 42)))))

(progn
  (it-sequential
    "Heap access keeps working for valid indices when UBSan mode is disabled."
    (let ((heap (cl-cc/runtime/memory:make-rt-heap)))
      (let ((cl-cc/runtime/memory:*rt-ubsan-enabled* nil))
        (cl-cc/runtime/memory:rt-heap-set heap 0 123)
        (expect (cl-cc/runtime/memory:rt-heap-ref heap 0) :to-equal 123))))
  (it-sequential
    "TSan flags a read from one thread-id context of a write left dirty by another, with no happens-before edge between them."
    (let ((heap (cl-cc/runtime/memory:make-rt-heap))
          (cl-cc/runtime/memory:*rt-tsan-enabled* t))
      (cl-cc/runtime/memory:rt-sanitizer-reset-state)
      (let ((cl-cc/runtime/memory:*rt-tsan-thread-id* 1))
        (cl-cc/runtime/memory:rt-heap-set heap 0 10))
      (let ((cl-cc/runtime/memory:*rt-tsan-thread-id* 2))
        (signals error (cl-cc/runtime/memory:rt-heap-ref heap 0)))))
  (it-sequential
    "TSan flags a write from one thread-id context racing a write left dirty by another, with no happens-before edge between them."
    (let ((heap (cl-cc/runtime/memory:make-rt-heap))
          (cl-cc/runtime/memory:*rt-tsan-enabled* t))
      (cl-cc/runtime/memory:rt-sanitizer-reset-state)
      (let ((cl-cc/runtime/memory:*rt-tsan-thread-id* 1))
        (cl-cc/runtime/memory:rt-heap-set heap 0 10))
      (let ((cl-cc/runtime/memory:*rt-tsan-thread-id* 2))
        (signals error (cl-cc/runtime/memory:rt-heap-set heap 0 20)))))
  (it-sequential
    "TSan does not flag reads from two thread-id contexts of a write that happened before the state reset."
    (let ((heap (cl-cc/runtime/memory:make-rt-heap)))
      (cl-cc/runtime/memory:rt-heap-set heap 0 10)
      (let ((cl-cc/runtime/memory:*rt-tsan-enabled* t))
        (cl-cc/runtime/memory:rt-sanitizer-reset-state)
        (let ((cl-cc/runtime/memory:*rt-tsan-thread-id* 1))
          (expect (cl-cc/runtime/memory:rt-heap-ref heap 0) :to-equal 10))
        (let ((cl-cc/runtime/memory:*rt-tsan-thread-id* 2))
          (expect (cl-cc/runtime/memory:rt-heap-ref heap 0) :to-equal 10)))))
  (it-sequential
    "%rt-tsan-current-thread-id returns different ids for the main thread and a spawned worker thread."
    (let ((cl-cc/runtime/memory:*rt-tsan-enabled* t))
      (cl-cc/runtime/memory:rt-sanitizer-reset-state)
      (let ((main-id
            (%rt-with-sanitizer-map-lock
              ()
              (%rt-tsan-current-thread-id)))
            (worker-id nil))
        (expect
          (%rt-with-sanitizer-map-lock
            ()
            (%rt-tsan-current-thread-id))
          :to-equal
          main-id)
        (sb-thread:join-thread
          (sb-thread:make-thread
            (lambda ()
              (setf worker-id (%rt-with-sanitizer-map-lock
                  ()
                  (%rt-tsan-current-thread-id))))))
        (expect (= main-id worker-id) :to-be-falsy)))))
