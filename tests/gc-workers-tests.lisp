;;;; tests/gc-workers-tests.lisp — Coverage for src/gc-workers.lisp
;;;;
;;;; FR-338 parallel GC worker foundation: SB-THREAD probing, work partitioning,
;;;; work-stealing queue primitives, task runners, and the parallel sweep entry.

(in-package :cl-cc-runtime/test)

(in-suite gc-suite)

;;; ------------------------------------------------------------
;;; SB-THREAD probing
;;; ------------------------------------------------------------

(deftest gc-workers-sb-thread-function-lookup
  "%rt-gc-sb-thread-function resolves live SB-THREAD symbols and NIL otherwise."
  (assert-true (functionp (cl-cc/runtime::%rt-gc-sb-thread-function "MAKE-THREAD")))
  (assert-null (cl-cc/runtime::%rt-gc-sb-thread-function "NO-SUCH-THREAD-SYMBOL")))

(deftest gc-workers-sb-thread-mutex-available
  "%rt-gc-sb-thread-mutex returns a usable mutex object on a threaded host."
  (assert-true (cl-cc/runtime::%rt-gc-sb-thread-mutex "gc-workers-test")))

(deftest gc-workers-detect-worker-count
  "rt-gc-detect-worker-count returns a non-negative integer worker count."
  (let ((n (cl-cc/runtime::rt-gc-detect-worker-count)))
    (assert-true (integerp n))
    (assert-true (>= n 0))))

;;; ------------------------------------------------------------
;;; Work partitioning
;;; ------------------------------------------------------------

(deftest gc-workers-partition-round-robin
  "%rt-gc-partition-list distributes items round-robin across worker buckets."
  (assert-equal '((1 4) (2 5) (3 6))
                (cl-cc/runtime::%rt-gc-partition-list '(1 2 3 4 5 6) 3)))

(deftest gc-workers-partition-clamps-zero-workers
  "Zero workers collapses to a single bucket holding all items."
  (assert-equal '((1 2 3))
                (cl-cc/runtime::%rt-gc-partition-list '(1 2 3) 0)))

;;; ------------------------------------------------------------
;;; Work-stealing queue primitives
;;; ------------------------------------------------------------

(deftest gc-workers-queue-pop-and-push
  "%rt-gc-queue-pop / %rt-gc-queue-push-list mutate a private worker queue cell."
  (let ((cell (cons '(1 2 3) nil)))
    (assert-= 1 (cl-cc/runtime::%rt-gc-queue-pop cell nil))
    (assert-equal '(2 3) (car cell))
    (cl-cc/runtime::%rt-gc-queue-push-list cell nil '(9 8))
    (assert-equal '(9 8 2 3) (car cell)))
  ;; Popping an empty queue yields NIL.
  (assert-null (cl-cc/runtime::%rt-gc-queue-pop (cons nil nil) nil)))

(deftest gc-workers-steal-one-from-peer
  "%rt-gc-steal-one takes a batch from a non-empty peer queue."
  (let* ((queues (vector (cons nil nil) (cons '(7 8 9) nil)))
         (cl-cc/runtime::*rt-gc-work-stealing-queues* queues)
         (cl-cc/runtime::*rt-gc-work-stealing-locks* nil))
    (let ((stolen (cl-cc/runtime::%rt-gc-steal-one 0 2)))
      (assert-= 2 (length stolen))
      (assert-true (member 7 stolen)))))

(deftest gc-workers-work-stealing-drain-collects
  "Without a processor, the drain moves local work into the results cell."
  (let* ((queues (vector (cons '(1 2 3) nil)))
         (cl-cc/runtime::*rt-gc-work-stealing-queues* queues)
         (cl-cc/runtime::*rt-gc-work-stealing-locks* nil)
         (cl-cc/runtime::*rt-gc-work-stealing-worker-index* 0)
         (cl-cc/runtime::*rt-gc-work-stealing-processor* nil)
         (results (cons nil nil)))
    (assert-= 3 (cl-cc/runtime::%rt-gc-work-stealing-drain (svref queues 0) results))
    (assert-= 3 (length (car results)))))

(deftest gc-workers-work-stealing-drain-invokes-processor
  "With a processor installed, the drain applies it to every drained item."
  (let* ((sum 0)
         (queues (vector (cons '(10 20) nil)))
         (cl-cc/runtime::*rt-gc-work-stealing-queues* queues)
         (cl-cc/runtime::*rt-gc-work-stealing-locks* nil)
         (cl-cc/runtime::*rt-gc-work-stealing-worker-index* 0)
         (cl-cc/runtime::*rt-gc-work-stealing-processor*
           (lambda (item queue) (declare (ignore queue)) (incf sum item))))
    (assert-= 2 (cl-cc/runtime::%rt-gc-work-stealing-drain
                 (svref queues 0) (cons nil nil)))
    (assert-= 30 sum)))

;;; ------------------------------------------------------------
;;; Task runners (sequential fallback path)
;;; ------------------------------------------------------------

(deftest gc-workers-run-worker-tasks-sequential
  "With zero workers, %rt-gc-run-worker-tasks runs each task in order."
  (let ((cl-cc/runtime::*gc-worker-count* 0))
    (assert-equal '(1 2 3)
                  (cl-cc/runtime::%rt-gc-run-worker-tasks
                   (list (lambda () 1) (lambda () 2) (lambda () 3))))))

(deftest gc-workers-run-workers-with-progress-sums
  "%rt-gc-run-workers-with-progress accumulates integer task results."
  (let ((cl-cc/runtime::*gc-worker-count* 0))
    (assert-= 6 (cl-cc/runtime::%rt-gc-run-workers-with-progress
                 (list (lambda () 1) (lambda () 2) (lambda () 3))
                 :phase :test))))

;;; ------------------------------------------------------------
;;; Parallel sweep entry point
;;; ------------------------------------------------------------

(deftest gc-workers-parallel-sweep-reclaims-dead
  "rt-gc-parallel-sweep reclaims an unmarked old-space object to the free-list."
  (let* ((heap (cl-cc/runtime::make-rt-heap :young-size 64 :old-size 64))
         (old-base (cl-cc/runtime::rt-heap-old-base heap)))
    (cl-cc/runtime::rt-heap-set-header
     heap old-base
     (cl-cc/runtime::make-rt-header 3 cl-cc/runtime:+rt-tag-cons+ :gc-bits 0))
    (setf (cl-cc/runtime::rt-heap-old-free heap) (+ old-base 3))
    (cl-cc/runtime::rt-gc-parallel-sweep heap 2)
    (assert-true (>= (cl-cc/runtime::rt-heap-words-collected heap) 3))
    (assert-true (not (null (cl-cc/runtime::rt-heap-free-list heap))))))
