;;;; gc-concurrent-sweep.lisp — Background worker-thread sweep pass, split out
;;;; of gc-major-sweep.lisp
(in-package :cl-cc/runtime)

(defun rt-gc-concurrent-sweep-worker (heap)
  "Sweep old space for FR-620 concurrent sweeping infrastructure."
  (check-type heap rt-heap)
  (if *gc-lazy-sweep-enabled*
      (progn
        (%rt-free-list-rebuild-bins heap nil)
        (setf (rt-heap-lazy-sweep-cursor heap) (rt-heap-old-base heap)
              (rt-heap-lazy-sweep-limit heap) (rt-heap-old-free heap))
        (loop while (< (rt-heap-lazy-sweep-cursor heap)
                       (rt-heap-lazy-sweep-limit heap)) do
          (rt-gc-lazy-sweep-step heap (rt-heap-lazy-sweep-cursor heap))))
      (%gc-sweep-old-space heap))
  heap)

(defun rt-gc-concurrent-sweep (heap)
  "Run the old-generation sweep worker on a host thread when available.

The worker function is separate so native runtimes can schedule it truly
concurrently with mutators.  The SBCL-hosted infrastructure joins before the
collector returns, preserving existing test-suite and allocation invariants while
still exercising the same concurrent sweep entry point."
  (check-type heap rt-heap)
  (let ((make-thread (%rt-resolve-sb-thread-function "MAKE-THREAD"))
        (join-thread (%rt-resolve-sb-thread-function "JOIN-THREAD")))
    (if (and make-thread join-thread)
        (let ((thread (ignore-errors
                        (funcall make-thread
                                 (lambda () (rt-gc-concurrent-sweep-worker heap))
                                 :name "cl-cc concurrent sweep"))))
          (if thread
              (unwind-protect
                   (progn
                     (setf *rt-concurrent-sweep-thread* thread)
                     (funcall join-thread thread))
                (setf *rt-concurrent-sweep-thread* nil))
              (rt-gc-concurrent-sweep-worker heap)))
        (rt-gc-concurrent-sweep-worker heap))))
