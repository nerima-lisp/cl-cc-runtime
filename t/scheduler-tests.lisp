;;;; t/scheduler-tests.lisp
;;;;
;;;; Tests for src/scheduler.lisp — the green-thread scheduler (priority ready
;;;; queues, sleeping/wake handling), the work-stealing scheduler (per-worker
;;;; deques, round-robin submission, stealing, dynamic growth), thread pools,
;;;; and the native OS-thread wrappers.
;;;;
;;;; Green threads are cooperative and run on the calling thread, so their tests
;;;; are deterministic single-thread drains.  The native-thread and thread-pool
;;;; tests use real OS threads and join every thread they spawn.

(in-package :cl-cc-runtime/test)

(in-suite cl-cc-unit-suite)

(defmacro with-fresh-scheduler (&body body)
  "Bind *rt-global-scheduler* to a brand-new scheduler for the duration of BODY."
  `(let ((cl-cc/runtime::*rt-global-scheduler* (cl-cc/runtime::rt-make-scheduler))
         (cl-cc/runtime::*rt-current-green-thread* nil))
     ,@body))

;;; ─── Scheduler init & priority ordering ─────────────────────────────────────

(deftest scheduler-init-sets-global
  "rt-scheduler-init installs a fresh global scheduler."
  (cl-cc/runtime::rt-scheduler-init)
  (assert-type cl-cc/runtime::rt-scheduler cl-cc/runtime::*rt-global-scheduler*))

(deftest scheduler-dequeue-honors-priority
  "%rt-scheduler-dequeue returns high-priority tasks before normal before low."
  (with-fresh-scheduler
    (let ((s cl-cc/runtime::*rt-global-scheduler*)
          (lo (cl-cc/runtime::%make-rt-green-thread :priority :low :thunk (lambda () :lo)))
          (no (cl-cc/runtime::%make-rt-green-thread :priority :normal :thunk (lambda () :no)))
          (hi (cl-cc/runtime::%make-rt-green-thread :priority :high :thunk (lambda () :hi))))
      (cl-cc/runtime::%rt-scheduler-enqueue s lo)
      (cl-cc/runtime::%rt-scheduler-enqueue s no)
      (cl-cc/runtime::%rt-scheduler-enqueue s hi)
      (assert-eq hi (cl-cc/runtime::%rt-scheduler-dequeue s))
      (assert-eq no (cl-cc/runtime::%rt-scheduler-dequeue s))
      (assert-eq lo (cl-cc/runtime::%rt-scheduler-dequeue s)))))

;;; ─── rt-spawn / run ─────────────────────────────────────────────────────────

(deftest scheduler-spawn-and-run-executes-thunk
  "Spawned green threads run to completion when the scheduler is drained."
  (with-fresh-scheduler
    (let ((n 0))
      (cl-cc/runtime::rt-spawn (lambda () (incf n)))
      (cl-cc/runtime::rt-spawn (lambda () (incf n)))
      (cl-cc/runtime::rt-spawn (lambda () (incf n)))
      (cl-cc/runtime::rt-scheduler-run)
      (assert-= 3 n))))

(deftest scheduler-spawn-priority-variants
  "rt-spawn-high and rt-spawn-low tag the created green thread's priority."
  (with-fresh-scheduler
    (assert-eq :high (cl-cc/runtime::rt-green-thread-priority
                      (cl-cc/runtime::rt-spawn-high (lambda () :x))))
    (assert-eq :low (cl-cc/runtime::rt-green-thread-priority
                     (cl-cc/runtime::rt-spawn-low (lambda () :y))))))

(deftest scheduler-run-once-runs-single-task
  "rt-scheduler-run with :once runs exactly one ready task and returns it."
  (with-fresh-scheduler
    (let ((n 0))
      (cl-cc/runtime::rt-spawn (lambda () (incf n)))
      (cl-cc/runtime::rt-spawn (lambda () (incf n)))
      (let ((th (cl-cc/runtime::rt-scheduler-run :once t)))
        (assert-type cl-cc/runtime::rt-green-thread th)
        (assert-= 1 n)))))

(deftest scheduler-run-records-result-and-status
  "A completed green thread records its result and :done status."
  (with-fresh-scheduler
    (let ((th (cl-cc/runtime::rt-spawn (lambda () (* 6 7)))))
      (cl-cc/runtime::rt-scheduler-run)
      (assert-eq :done (cl-cc/runtime::rt-green-thread-status th))
      (assert-= 42 (cl-cc/runtime::rt-green-thread-result th)))))

(deftest scheduler-run-captures-thread-error
  "An erroring green thread ends :failed with the condition captured."
  (with-fresh-scheduler
    (let ((th (cl-cc/runtime::rt-spawn (lambda () (error "task boom")))))
      (cl-cc/runtime::rt-scheduler-run)
      (assert-eq :failed (cl-cc/runtime::rt-green-thread-status th))
      (assert-type error (cl-cc/runtime::rt-green-thread-error th)))))

(deftest scheduler-cancelled-thread-skipped
  "A green thread cancelled before running ends :cancelled without executing."
  (with-fresh-scheduler
    (let* ((ran nil)
           (th (cl-cc/runtime::rt-spawn (lambda () (setf ran t)))))
      (setf (cl-cc/runtime::rt-green-thread-cancelled-p th) t)
      (cl-cc/runtime::rt-scheduler-run)
      (assert-eq :cancelled (cl-cc/runtime::rt-green-thread-status th))
      (assert-false ran))))

;;; ─── yield / current id ─────────────────────────────────────────────────────

(deftest scheduler-yield-reenqueues-current
  "rt-yield re-enqueues the currently running green thread."
  (with-fresh-scheduler
    (let ((th (cl-cc/runtime::%make-rt-green-thread :thunk (lambda () :x))))
      (let ((cl-cc/runtime::*rt-current-green-thread* th))
        (cl-cc/runtime::rt-yield))
      (assert-true (member th (cl-cc/runtime::rt-scheduler-ready
                               cl-cc/runtime::*rt-global-scheduler*))))))

(deftest scheduler-current-thread-id
  "rt-current-thread-id returns the running green thread's id."
  (let ((th (cl-cc/runtime::%make-rt-green-thread :id 77)))
    (let ((cl-cc/runtime::*rt-current-green-thread* th))
      (assert-= 77 (cl-cc/runtime::rt-current-thread-id)))))

;;; ─── sleep / wake ───────────────────────────────────────────────────────────

(deftest scheduler-sleep-then-wake
  "rt-sleep-task parks the current thread; %rt-scheduler-wake-sleepers requeues
it once its wake time has passed."
  (with-fresh-scheduler
    (let* ((s cl-cc/runtime::*rt-global-scheduler*)
           (th (cl-cc/runtime::%make-rt-green-thread :thunk (lambda () :x))))
      (let ((cl-cc/runtime::*rt-current-green-thread* th))
        (cl-cc/runtime::rt-sleep-task 0.0))
      (assert-eq :sleeping (cl-cc/runtime::rt-green-thread-status th))
      (assert-true (member th (cl-cc/runtime::rt-scheduler-sleeping s)))
      ;; wake-time is now-ish; ensure the clock has advanced past it.
      (sleep 0.005)
      (cl-cc/runtime::%rt-scheduler-wake-sleepers s)
      (assert-eq :ready (cl-cc/runtime::rt-green-thread-status th))
      (assert-false (member th (cl-cc/runtime::rt-scheduler-sleeping s)))
      (assert-true (member th (cl-cc/runtime::rt-scheduler-ready s))))))

;;; ─── Work deque ─────────────────────────────────────────────────────────────

(deftest work-deque-owner-is-lifo
  "The owner pushes and pops at the front: pop returns most-recently pushed."
  (let ((d (cl-cc/runtime::make-rt-work-deque)))
    (cl-cc/runtime::rt-work-deque-push-front d 1)
    (cl-cc/runtime::rt-work-deque-push-front d 2)
    (cl-cc/runtime::rt-work-deque-push-front d 3)
    (assert-= 3 (cl-cc/runtime::rt-work-deque-count d))
    (assert-= 3 (cl-cc/runtime::rt-work-deque-pop-front d))
    (assert-= 2 (cl-cc/runtime::rt-work-deque-pop-front d))
    (assert-= 1 (cl-cc/runtime::rt-work-deque-pop-front d))))

(deftest work-deque-steal-takes-oldest
  "A thief steals from the back, taking the oldest-pushed task (FIFO steal)."
  (let ((d (cl-cc/runtime::make-rt-work-deque)))
    (cl-cc/runtime::rt-work-deque-push-front d :oldest)
    (cl-cc/runtime::rt-work-deque-push-front d :middle)
    (cl-cc/runtime::rt-work-deque-push-front d :newest)
    (assert-eq :oldest (cl-cc/runtime::rt-work-deque-steal-back d))
    (assert-= 2 (cl-cc/runtime::rt-work-deque-count d))))

(deftest work-deque-steal-single-item
  "Stealing the sole item empties the deque."
  (let ((d (cl-cc/runtime::make-rt-work-deque)))
    (cl-cc/runtime::rt-work-deque-push-front d :only)
    (assert-eq :only (cl-cc/runtime::rt-work-deque-steal-back d))
    (assert-= 0 (cl-cc/runtime::rt-work-deque-count d))))

(deftest work-deque-steal-empty-returns-nil
  "Stealing from an empty deque returns NIL."
  (let ((d (cl-cc/runtime::make-rt-work-deque)))
    (assert-null (cl-cc/runtime::rt-work-deque-steal-back d))))

;;; ─── Work-stealing scheduler ────────────────────────────────────────────────

(deftest work-stealing-make-creates-workers
  "rt-make-work-stealing-scheduler builds the requested number of workers."
  (let ((s (cl-cc/runtime::rt-make-work-stealing-scheduler :workers 3)))
    (assert-= 3 (length (cl-cc/runtime::rt-work-stealing-scheduler-workers s)))))

(deftest work-stealing-submit-round-robins
  "Submissions are distributed round-robin across workers."
  (let* ((s (cl-cc/runtime::rt-make-work-stealing-scheduler :workers 2))
         (workers (cl-cc/runtime::rt-work-stealing-scheduler-workers s)))
    (dotimes (i 4) (cl-cc/runtime::rt-work-stealing-submit s (lambda () i)))
    (assert-= 2 (cl-cc/runtime::rt-work-deque-count
                 (cl-cc/runtime::rt-worker-deque (first workers))))
    (assert-= 2 (cl-cc/runtime::rt-work-deque-count
                 (cl-cc/runtime::rt-worker-deque (second workers))))))

(deftest work-stealing-submit-requires-function
  "rt-work-stealing-submit type-checks its thunk."
  (let ((s (cl-cc/runtime::rt-make-work-stealing-scheduler :workers 1)))
    (assert-signals type-error (cl-cc/runtime::rt-work-stealing-submit s :not-a-fn))))

(deftest work-stealing-run-drains-all
  "rt-work-stealing-run executes every submitted task across all workers."
  (let ((s (cl-cc/runtime::rt-make-work-stealing-scheduler :workers 2))
        (n 0))
    (dotimes (i 6) (cl-cc/runtime::rt-work-stealing-submit s (lambda () (incf n))))
    (cl-cc/runtime::rt-work-stealing-run s)
    (assert-= 6 n)))

(deftest work-stealing-worker-steals-from-victim
  "A worker with an empty deque steals a task from another worker's deque."
  (let* ((s (cl-cc/runtime::rt-make-work-stealing-scheduler :workers 2))
         (workers (cl-cc/runtime::rt-work-stealing-scheduler-workers s))
         (w0 (first workers))
         (w1 (second workers))
         (task (cl-cc/runtime::%make-rt-green-thread :thunk (lambda () :t))))
    (cl-cc/runtime::rt-work-deque-push-front (cl-cc/runtime::rt-worker-deque w0) task)
    (assert-eq task (cl-cc/runtime::%rt-worker-steal w1))
    (assert-= 1 (cl-cc/runtime::rt-worker-steals w1))))

(deftest work-stealing-run-once-executes-and-counts
  "rt-worker-run-once runs a task from the worker's own deque and counts it."
  (let* ((s (cl-cc/runtime::rt-make-work-stealing-scheduler :workers 1))
         (w (first (cl-cc/runtime::rt-work-stealing-scheduler-workers s)))
         (ran nil))
    (cl-cc/runtime::rt-work-stealing-submit s (lambda () (setf ran t)))
    (assert-true (cl-cc/runtime::rt-worker-run-once w))
    (assert-true ran)
    (assert-= 1 (cl-cc/runtime::rt-worker-tasks-executed w))))

(deftest work-stealing-maybe-grow-adds-worker
  "maybe-grow adds a worker when all deques have backlog and capacity remains."
  (let ((s (cl-cc/runtime::rt-make-work-stealing-scheduler :workers 1 :max-workers 2)))
    (cl-cc/runtime::rt-work-stealing-submit s (lambda () :backlog))
    (let ((grown (cl-cc/runtime::rt-work-stealing-maybe-grow s)))
      (assert-type cl-cc/runtime::rt-worker grown)
      (assert-= 2 (length (cl-cc/runtime::rt-work-stealing-scheduler-workers s))))))

(deftest work-stealing-maybe-grow-respects-max
  "maybe-grow does nothing when already at the worker cap."
  (let ((s (cl-cc/runtime::rt-make-work-stealing-scheduler :workers 1 :max-workers 1)))
    (cl-cc/runtime::rt-work-stealing-submit s (lambda () :x))
    (assert-null (cl-cc/runtime::rt-work-stealing-maybe-grow s))))

;;; ─── rt-scheduler-steal across victim types ─────────────────────────────────

(deftest scheduler-steal-from-plain-scheduler
  "rt-scheduler-steal pulls a task out of a classic priority scheduler."
  (let ((s (cl-cc/runtime::rt-make-scheduler))
        (th (cl-cc/runtime::%make-rt-green-thread :priority :normal :thunk (lambda () :x))))
    (cl-cc/runtime::%rt-scheduler-enqueue s th)
    (assert-eq th (cl-cc/runtime::rt-scheduler-steal s))))

(deftest scheduler-steal-from-worker-and-ws
  "rt-scheduler-steal handles rt-worker and rt-work-stealing-scheduler victims."
  (let* ((ws (cl-cc/runtime::rt-make-work-stealing-scheduler :workers 1))
         (w (first (cl-cc/runtime::rt-work-stealing-scheduler-workers ws)))
         (task (cl-cc/runtime::%make-rt-green-thread :thunk (lambda () :x))))
    (cl-cc/runtime::rt-work-deque-push-front (cl-cc/runtime::rt-worker-deque w) task)
    ;; Steal via the work-stealing scheduler dispatch.
    (assert-eq task (cl-cc/runtime::rt-scheduler-steal ws))
    ;; And directly via a worker victim.
    (cl-cc/runtime::rt-work-deque-push-front (cl-cc/runtime::rt-worker-deque w) task)
    (assert-eq task (cl-cc/runtime::rt-scheduler-steal w))))

;;; ─── Thread pool (deterministic drain) ──────────────────────────────────────

(deftest thread-pool-submit-and-run
  "A pool's submitted tasks run when the pool scheduler is drained on this
thread."
  (let ((pool (cl-cc/runtime::rt-make-thread-pool :size 1))
        (n 0))
    (cl-cc/runtime::rt-thread-pool-submit pool (lambda () (incf n)))
    (cl-cc/runtime::rt-thread-pool-submit pool (lambda () (incf n)))
    (cl-cc/runtime::rt-thread-pool-run pool)
    (assert-= 2 n)))

(deftest thread-pool-start-runs-on-real-thread
  "rt-thread-pool-start launches a worker OS thread that drains submitted work;
shutdown then lets it exit and be joined."
  (let ((pool (cl-cc/runtime::rt-make-thread-pool :size 1))
        (box (list nil)))
    (cl-cc/runtime::rt-thread-pool-submit pool (lambda () (setf (first box) t)))
    (cl-cc/runtime::rt-thread-pool-start pool)
    (cl-weave:expect-poll (lambda () (first box))
                          (:timeout-ms 3000 :interval-ms 5) :to-be-truthy)
    (cl-cc/runtime::rt-thread-pool-shutdown pool)
    (dolist (th (cl-cc/runtime::rt-thread-pool-threads pool))
      (sb-thread:join-thread th))
    (assert-true (first box))))

;;; ─── Native OS threads ──────────────────────────────────────────────────────

(deftest native-thread-join-returns-value
  "rt-make-thread runs a real OS thread; rt-thread-join returns its result."
  (let ((th (cl-cc/runtime::rt-make-thread (lambda () (+ 40 2)))))
    (assert-= 42 (cl-cc/runtime::rt-thread-join th))
    (assert-false (cl-cc/runtime::rt-thread-alive-p th))))

(deftest native-thread-name-preserved
  "A named native thread reports its name."
  (let ((th (cl-cc/runtime::rt-make-thread (lambda () 1) :name "namer")))
    (cl-cc/runtime::rt-thread-join th)
    (assert-string= "namer" (cl-cc/runtime::rt-thread-name th))))

(deftest native-thread-error-captured-and-propagates-on-join
  "A native thread whose function errors ends :failed with the condition stored
on the wrapper (not re-signalled inside the worker, which would crash the
process in batch mode); rt-thread-join then re-signals it in the joiner."
  (let ((th (cl-cc/runtime::rt-make-thread (lambda () (error "native boom")))))
    (assert-signals error (cl-cc/runtime::rt-thread-join th))
    (assert-eq :failed (cl-cc/runtime::rt-native-thread-state th))
    (assert-type error (cl-cc/runtime::rt-native-thread-error th))))

(deftest native-thread-make-type-checks
  "rt-make-thread requires an actual function."
  (assert-signals type-error (cl-cc/runtime::rt-make-thread :not-a-fn)))

(deftest native-current-thread-and-all-threads
  "rt-current-thread returns a wrapper; rt-all-threads includes at least it."
  (let ((cur (cl-cc/runtime::rt-current-thread)))
    (assert-type cl-cc/runtime::rt-native-thread cur)
    (assert-true (plusp (length (cl-cc/runtime::rt-all-threads))))))

(deftest native-thread-yield-returns-t
  "rt-thread-yield yields the CPU and returns T."
  (assert-true (cl-cc/runtime::rt-thread-yield)))

;;; ─── Property: priority dequeue never returns lower before higher ───────────

(cl-weave:it-property "high-priority tasks always dequeue before low-priority ones"
    ((highs (cl-weave:gen-integer :min 0 :max 5))
     (lows (cl-weave:gen-integer :min 0 :max 5)))
  (let ((s (cl-cc/runtime::rt-make-scheduler)))
    (dotimes (i lows)
      (cl-cc/runtime::%rt-scheduler-enqueue
       s (cl-cc/runtime::%make-rt-green-thread :priority :low :thunk (lambda () :l))))
    (dotimes (i highs)
      (cl-cc/runtime::%rt-scheduler-enqueue
       s (cl-cc/runtime::%make-rt-green-thread :priority :high :thunk (lambda () :h))))
    ;; Dequeue everything, collecting priorities in order.
    (let ((order (loop for th = (cl-cc/runtime::%rt-scheduler-dequeue s)
                       while th collect (cl-cc/runtime::rt-green-thread-priority th))))
      ;; All :high entries must precede every :low entry.
      (let ((pos-last-high (position :high order :from-end t))
            (pos-first-low (position :low order)))
        (or (null pos-last-high) (null pos-first-low)
            (< pos-last-high pos-first-low))))))
