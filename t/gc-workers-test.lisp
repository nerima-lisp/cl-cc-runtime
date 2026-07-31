;;;; t/gc-workers-test.lisp — Coverage for src/gc-workers.lisp
;;;;
;;;; FR-338 parallel GC worker foundation: SB-THREAD probing, work partitioning,
;;;; work-stealing queue primitives, task runners, and the parallel sweep entry.
(in-package :cl-cc-runtime/test)

;;; ------------------------------------------------------------
;;; SB-THREAD probing
;;; ------------------------------------------------------------
;;; %rt-resolve-sb-thread-function lives in heap-sanitizer.lisp (shared by
;;; every optional-locking macro in this tree; see its docstring), but
;;; gc-workers.lisp's own %rt-gc-sb-thread-mutex/%rt-gc-with-optional-mutex
;;; are its most direct consumers here.
(it-sequential
  "%rt-resolve-sb-thread-function resolves live SB-THREAD symbols and NIL otherwise."
  (expect
    (functionp (cl-cc/runtime::%rt-resolve-sb-thread-function "MAKE-THREAD"))
    :to-be-truthy)
  (expect
    (cl-cc/runtime::%rt-resolve-sb-thread-function "NO-SUCH-THREAD-SYMBOL")
    :to-be-null))

(it-sequential
  "%rt-gc-sb-thread-mutex returns a usable mutex object on a threaded host."
  (expect (cl-cc/runtime::%rt-gc-sb-thread-mutex "gc-workers-test") :to-be-truthy))

(it-sequential
  "rt-gc-detect-worker-count returns a non-negative integer worker count."
  (let ((n (cl-cc/runtime::rt-gc-detect-worker-count)))
    (expect (integerp n) :to-be-truthy)
    (expect (>= n 0) :to-be-truthy)))

;;; ------------------------------------------------------------
;;; Work partitioning
;;; ------------------------------------------------------------
(it-sequential
  "%rt-gc-partition-list distributes items round-robin across worker buckets."
  (expect
    (cl-cc/runtime::%rt-gc-partition-list '(1 2 3 4 5 6) 3)
    :to-equal
    '((1 4) (2 5) (3 6))))

(it-sequential
  "Zero workers collapses to a single bucket holding all items."
  (expect (cl-cc/runtime::%rt-gc-partition-list '(1 2 3) 0) :to-equal '((1 2 3))))

;;; ------------------------------------------------------------
;;; Work-stealing queue primitives
;;; ------------------------------------------------------------
(it-sequential "%rt-gc-queue-pop / %rt-gc-queue-push-list mutate a private worker queue cell." (let ((cell (cons '(1 2 3) nil)))
    (expect (cl-cc/runtime::%rt-gc-queue-pop cell nil) :to-equal 1)
    (expect (car cell) :to-equal '(2 3))
    (cl-cc/runtime::%rt-gc-queue-push-list cell nil '(9 8))
    (expect (car cell) :to-equal '(9 8 2 3)))
  ;; Popping an empty queue yields NIL.
  (expect (cl-cc/runtime::%rt-gc-queue-pop (cons nil nil) nil) :to-be-null))

(it-sequential
  "%rt-gc-steal-one takes a batch from a non-empty peer queue."
  (let* ((queues (vector (cons nil nil) (cons '(7 8 9) nil)))
         (cl-cc/runtime::*rt-gc-work-stealing-queues* queues)
         (cl-cc/runtime::*rt-gc-work-stealing-locks* nil))
    (let ((stolen (cl-cc/runtime::%rt-gc-steal-one 0 2)))
      (expect (length stolen) :to-equal 2)
      (expect (member 7 stolen) :to-be-truthy))))

(it-sequential
  "Without a processor, the drain moves local work into the results cell."
  (let* ((queues (vector (cons '(1 2 3) nil)))
         (cl-cc/runtime::*rt-gc-work-stealing-queues* queues)
         (cl-cc/runtime::*rt-gc-work-stealing-locks* nil)
         (cl-cc/runtime::*rt-gc-work-stealing-worker-index* 0)
         (cl-cc/runtime::*rt-gc-work-stealing-processor* nil)
         (results (cons nil nil)))
    (expect
      (cl-cc/runtime::%rt-gc-work-stealing-drain (svref queues 0) results)
      :to-equal
      3)
    (expect (length (car results)) :to-equal 3)))

(it-sequential
  "With a processor installed, the drain applies it to every drained item."
  (let* ((sum 0)
         (queues (vector (cons '(10 20) nil)))
         (cl-cc/runtime::*rt-gc-work-stealing-queues* queues)
         (cl-cc/runtime::*rt-gc-work-stealing-locks* nil)
         (cl-cc/runtime::*rt-gc-work-stealing-worker-index* 0)
         (cl-cc/runtime::*rt-gc-work-stealing-processor*
        (lambda (item queue)
          (declare (ignore queue))
          (incf sum item))))
    (expect
      (cl-cc/runtime::%rt-gc-work-stealing-drain (svref queues 0) (cons nil nil))
      :to-equal
      2)
    (expect sum :to-equal 30)))

;;; ------------------------------------------------------------
;;; Task runners (sequential fallback path)
;;; ------------------------------------------------------------
(it-sequential
  "With zero workers, %rt-gc-run-worker-tasks runs each task in order."
  (let ((cl-cc/runtime::*gc-worker-count* 0))
    (expect
      (cl-cc/runtime::%rt-gc-run-worker-tasks
        (list
          (lambda ()
            1)
          (lambda ()
            2)
          (lambda ()
            3)))
      :to-equal
      '(1 2 3))))

(it-sequential
  "%rt-gc-run-workers-with-progress accumulates integer task results."
  (let ((cl-cc/runtime::*gc-worker-count* 0))
    (expect
      (cl-cc/runtime::%rt-gc-run-workers-with-progress
        (list
          (lambda ()
            1)
          (lambda ()
            2)
          (lambda ()
            3))
        :phase
        :test)
      :to-equal
      6)))

;;; ------------------------------------------------------------
;;; Parallel sweep entry point
;;; ------------------------------------------------------------
(it-sequential
  "rt-gc-parallel-sweep reclaims an unmarked old-space object to the free-list."
  (let* ((heap (cl-cc/runtime::make-rt-heap :young-size 64 :old-size 64))
         (old-base (cl-cc/runtime::rt-heap-old-base heap)))
    (cl-cc/runtime::rt-heap-set-header
      heap
      old-base
      (cl-cc/runtime::make-rt-header 3 cl-cc/runtime:+rt-tag-cons+ :gc-bits 0))
    (setf (cl-cc/runtime::rt-heap-old-free heap) (+ old-base 3))
    (cl-cc/runtime::rt-gc-parallel-sweep heap 2)
    (expect (>= (cl-cc/runtime::rt-heap-words-collected heap) 3) :to-be-truthy)
    (expect (not (null (cl-cc/runtime::rt-heap-free-list heap))) :to-be-truthy)))
