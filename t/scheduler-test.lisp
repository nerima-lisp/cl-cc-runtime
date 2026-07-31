;;;; t/scheduler-test.lisp
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

(defmacro with-fresh-scheduler (&body body)
  "Bind *rt-global-scheduler* to a brand-new scheduler for the duration of BODY."
  `(let ((cl-cc/runtime::*rt-global-scheduler* (cl-cc/runtime::rt-make-scheduler))
        (cl-cc/runtime::*rt-current-green-thread* nil))
    ,@body))

;;; ─── Scheduler init & priority ordering ─────────────────────────────────────
(it-sequential
  "rt-scheduler-init installs a fresh global scheduler."
  (cl-cc/runtime::rt-scheduler-init)
  (expect
    (typep cl-cc/runtime::*rt-global-scheduler* (quote cl-cc/runtime::rt-scheduler))
    :to-be-truthy))

(it-sequential
  "%rt-scheduler-dequeue returns high-priority tasks before normal before low."
  (with-fresh-scheduler
    (let ((s cl-cc/runtime::*rt-global-scheduler*)
          (lo
          (cl-cc/runtime::%make-rt-green-thread
            :priority
            :low
            :thunk
            (lambda ()
              :lo)))
          (no
          (cl-cc/runtime::%make-rt-green-thread
            :priority
            :normal
            :thunk
            (lambda ()
              :no)))
          (hi
          (cl-cc/runtime::%make-rt-green-thread
            :priority
            :high
            :thunk
            (lambda ()
              :hi))))
      (cl-cc/runtime::%rt-scheduler-enqueue s lo)
      (cl-cc/runtime::%rt-scheduler-enqueue s no)
      (cl-cc/runtime::%rt-scheduler-enqueue s hi)
      (expect (cl-cc/runtime::%rt-scheduler-dequeue s) :to-be hi)
      (expect (cl-cc/runtime::%rt-scheduler-dequeue s) :to-be no)
      (expect (cl-cc/runtime::%rt-scheduler-dequeue s) :to-be lo))))

;;; ─── rt-spawn / run ─────────────────────────────────────────────────────────
(it-sequential
  "Spawned green threads run to completion when the scheduler is drained."
  (with-fresh-scheduler
    (let ((n 0))
      (cl-cc/runtime::rt-spawn
        (lambda ()
          (incf n)))
      (cl-cc/runtime::rt-spawn
        (lambda ()
          (incf n)))
      (cl-cc/runtime::rt-spawn
        (lambda ()
          (incf n)))
      (cl-cc/runtime::rt-scheduler-run)
      (expect n :to-equal 3))))

(it-sequential
  "rt-spawn-high and rt-spawn-low tag the created green thread's priority."
  (with-fresh-scheduler
    (expect
      (cl-cc/runtime::rt-green-thread-priority
        (cl-cc/runtime::rt-spawn-high
          (lambda ()
            :x)))
      :to-be
      :high)
    (expect
      (cl-cc/runtime::rt-green-thread-priority
        (cl-cc/runtime::rt-spawn-low
          (lambda ()
            :y)))
      :to-be
      :low)))

(it-sequential
  "rt-scheduler-run with :once runs exactly one ready task and returns it."
  (with-fresh-scheduler
    (let ((n 0))
      (cl-cc/runtime::rt-spawn
        (lambda ()
          (incf n)))
      (cl-cc/runtime::rt-spawn
        (lambda ()
          (incf n)))
      (let ((th (cl-cc/runtime::rt-scheduler-run :once t)))
        (expect (typep th (quote cl-cc/runtime::rt-green-thread)) :to-be-truthy)
        (expect n :to-equal 1)))))

(it-sequential
  "A completed green thread records its result and :done status."
  (with-fresh-scheduler
    (let ((th
          (cl-cc/runtime::rt-spawn
            (lambda ()
              (* 6 7)))))
      (cl-cc/runtime::rt-scheduler-run)
      (expect (cl-cc/runtime::rt-green-thread-status th) :to-be :done)
      (expect (cl-cc/runtime::rt-green-thread-result th) :to-equal 42))))

(it-sequential
  "An erroring green thread ends :failed with the condition captured."
  (with-fresh-scheduler
    (let ((th
          (cl-cc/runtime::rt-spawn
            (lambda ()
              (error "task boom")))))
      (cl-cc/runtime::rt-scheduler-run)
      (expect (cl-cc/runtime::rt-green-thread-status th) :to-be :failed)
      (expect
        (typep (cl-cc/runtime::rt-green-thread-error th) (quote error))
        :to-be-truthy))))

(it-sequential
  "A green thread cancelled before running ends :cancelled without executing."
  (with-fresh-scheduler
    (let* ((ran nil)
           (th
          (cl-cc/runtime::rt-spawn
            (lambda ()
              (setf ran t)))))
      (setf (cl-cc/runtime::rt-green-thread-cancelled-p th) t)
      (cl-cc/runtime::rt-scheduler-run)
      (expect (cl-cc/runtime::rt-green-thread-status th) :to-be :cancelled)
      (expect ran :to-be-falsy))))

;;; ─── yield / current id ─────────────────────────────────────────────────────
(it-sequential
  "rt-yield re-enqueues the currently running green thread."
  (with-fresh-scheduler
    (let ((th
          (cl-cc/runtime::%make-rt-green-thread
            :thunk
            (lambda ()
              :x))))
      (let ((cl-cc/runtime::*rt-current-green-thread* th))
        (cl-cc/runtime::rt-yield))
      (expect
        (member
          th
          (cl-cc/runtime::rt-scheduler-ready cl-cc/runtime::*rt-global-scheduler*))
        :to-be-truthy))))

(it-sequential
  "rt-current-thread-id returns the running green thread's id."
  (let ((th (cl-cc/runtime::%make-rt-green-thread :id 77)))
    (let ((cl-cc/runtime::*rt-current-green-thread* th))
      (expect (cl-cc/runtime::rt-current-thread-id) :to-equal 77))))

;;; ─── sleep / wake ───────────────────────────────────────────────────────────
(it-sequential "rt-sleep-task parks the current thread; %rt-scheduler-wake-sleepers requeues
it once its wake time has passed." (with-fresh-scheduler
    (let* ((s cl-cc/runtime::*rt-global-scheduler*)
           (th (cl-cc/runtime::%make-rt-green-thread :thunk (lambda () :x))))
      (let ((cl-cc/runtime::*rt-current-green-thread* th))
        (cl-cc/runtime::rt-sleep-task 0.0))
      (expect (cl-cc/runtime::rt-green-thread-status th) :to-be :sleeping)
      (expect (member th (cl-cc/runtime::rt-scheduler-sleeping s)) :to-be-truthy)
      ;; wake-time is now-ish; ensure the clock has advanced past it.
      (sleep 0.005)
      (cl-cc/runtime::%rt-scheduler-wake-sleepers s)
      (expect (cl-cc/runtime::rt-green-thread-status th) :to-be :ready)
      (expect (member th (cl-cc/runtime::rt-scheduler-sleeping s)) :to-be-falsy)
      (expect (member th (cl-cc/runtime::rt-scheduler-ready s)) :to-be-truthy))))

;;; ─── Work deque ─────────────────────────────────────────────────────────────
(it-sequential
  "The owner pushes and pops at the front: pop returns most-recently pushed."
  (let ((d (cl-cc/runtime::make-rt-work-deque)))
    (cl-cc/runtime::rt-work-deque-push-front d 1)
    (cl-cc/runtime::rt-work-deque-push-front d 2)
    (cl-cc/runtime::rt-work-deque-push-front d 3)
    (expect (cl-cc/runtime::rt-work-deque-count d) :to-equal 3)
    (expect (cl-cc/runtime::rt-work-deque-pop-front d) :to-equal 3)
    (expect (cl-cc/runtime::rt-work-deque-pop-front d) :to-equal 2)
    (expect (cl-cc/runtime::rt-work-deque-pop-front d) :to-equal 1)))

(it-sequential
  "A thief steals from the back, taking the oldest-pushed task (FIFO steal)."
  (let ((d (cl-cc/runtime::make-rt-work-deque)))
    (cl-cc/runtime::rt-work-deque-push-front d :oldest)
    (cl-cc/runtime::rt-work-deque-push-front d :middle)
    (cl-cc/runtime::rt-work-deque-push-front d :newest)
    (expect (cl-cc/runtime::rt-work-deque-steal-back d) :to-be :oldest)
    (expect (cl-cc/runtime::rt-work-deque-count d) :to-equal 2)))

(it-sequential
  "Stealing the sole item empties the deque."
  (let ((d (cl-cc/runtime::make-rt-work-deque)))
    (cl-cc/runtime::rt-work-deque-push-front d :only)
    (expect (cl-cc/runtime::rt-work-deque-steal-back d) :to-be :only)
    (expect (cl-cc/runtime::rt-work-deque-count d) :to-equal 0)))

(it-sequential
  "Stealing from an empty deque returns NIL."
  (let ((d (cl-cc/runtime::make-rt-work-deque)))
    (expect (cl-cc/runtime::rt-work-deque-steal-back d) :to-be-null)))

;;; ─── Work-stealing scheduler ────────────────────────────────────────────────
(it-sequential
  "rt-make-work-stealing-scheduler builds the requested number of workers."
  (let ((s (cl-cc/runtime::rt-make-work-stealing-scheduler :workers 3)))
    (expect
      (length (cl-cc/runtime::rt-work-stealing-scheduler-workers s))
      :to-equal
      3)))

(it-sequential
  "Submissions are distributed round-robin across workers."
  (let* ((s (cl-cc/runtime::rt-make-work-stealing-scheduler :workers 2))
         (workers (cl-cc/runtime::rt-work-stealing-scheduler-workers s)))
    (dotimes (i 4)
      (cl-cc/runtime::rt-work-stealing-submit
        s
        (lambda ()
          i)))
    (expect
      (cl-cc/runtime::rt-work-deque-count
        (cl-cc/runtime::rt-worker-deque (first workers)))
      :to-equal
      2)
    (expect
      (cl-cc/runtime::rt-work-deque-count
        (cl-cc/runtime::rt-worker-deque (second workers)))
      :to-equal
      2)))

(it-sequential
  "rt-work-stealing-submit type-checks its thunk."
  (let ((s (cl-cc/runtime::rt-make-work-stealing-scheduler :workers 1)))
    (signals type-error (cl-cc/runtime::rt-work-stealing-submit s :not-a-fn))))

(it-sequential
  "rt-work-stealing-run executes every submitted task across all workers."
  (let ((s (cl-cc/runtime::rt-make-work-stealing-scheduler :workers 2))
        (n 0))
    (dotimes (i 6)
      (cl-cc/runtime::rt-work-stealing-submit
        s
        (lambda ()
          (incf n))))
    (cl-cc/runtime::rt-work-stealing-run s)
    (expect n :to-equal 6)))

(it-sequential
  "A worker with an empty deque steals a task from another worker's deque."
  (let* ((s (cl-cc/runtime::rt-make-work-stealing-scheduler :workers 2))
         (workers (cl-cc/runtime::rt-work-stealing-scheduler-workers s))
         (w0 (first workers))
         (w1 (second workers))
         (task
        (cl-cc/runtime::%make-rt-green-thread
          :thunk
          (lambda ()
            :t))))
    (cl-cc/runtime::rt-work-deque-push-front
      (cl-cc/runtime::rt-worker-deque w0)
      task)
    (expect (cl-cc/runtime::%rt-worker-steal w1) :to-be task)
    (expect (cl-cc/runtime::rt-worker-steals w1) :to-equal 1)))

(it-sequential
  "rt-worker-run-once runs a task from the worker's own deque and counts it."
  (let* ((s (cl-cc/runtime::rt-make-work-stealing-scheduler :workers 1))
         (w (first (cl-cc/runtime::rt-work-stealing-scheduler-workers s)))
         (ran nil))
    (cl-cc/runtime::rt-work-stealing-submit
      s
      (lambda ()
        (setf ran t)))
    (expect (cl-cc/runtime::rt-worker-run-once w) :to-be-truthy)
    (expect ran :to-be-truthy)
    (expect (cl-cc/runtime::rt-worker-tasks-executed w) :to-equal 1)))

(it-sequential
  "maybe-grow adds a worker when all deques have backlog and capacity remains."
  (let ((s (cl-cc/runtime::rt-make-work-stealing-scheduler :workers 1 :max-workers 2)))
    (cl-cc/runtime::rt-work-stealing-submit
      s
      (lambda ()
        :backlog))
    (let ((grown (cl-cc/runtime::rt-work-stealing-maybe-grow s)))
      (expect (typep grown (quote cl-cc/runtime::rt-worker)) :to-be-truthy)
      (expect
        (length (cl-cc/runtime::rt-work-stealing-scheduler-workers s))
        :to-equal
        2))))

(it-sequential
  "maybe-grow does nothing when already at the worker cap."
  (let ((s (cl-cc/runtime::rt-make-work-stealing-scheduler :workers 1 :max-workers 1)))
    (cl-cc/runtime::rt-work-stealing-submit
      s
      (lambda ()
        :x))
    (expect (cl-cc/runtime::rt-work-stealing-maybe-grow s) :to-be-null)))

;;; ─── rt-scheduler-steal across victim types ─────────────────────────────────
(it-sequential
  "rt-scheduler-steal pulls a task out of a classic priority scheduler."
  (let ((s (cl-cc/runtime::rt-make-scheduler))
        (th
        (cl-cc/runtime::%make-rt-green-thread
          :priority
          :normal
          :thunk
          (lambda ()
            :x))))
    (cl-cc/runtime::%rt-scheduler-enqueue s th)
    (expect (cl-cc/runtime::rt-scheduler-steal s) :to-be th)))

(it-sequential "rt-scheduler-steal handles rt-worker and rt-work-stealing-scheduler victims." (let* ((ws (cl-cc/runtime::rt-make-work-stealing-scheduler :workers 1))
         (w (first (cl-cc/runtime::rt-work-stealing-scheduler-workers ws)))
         (task (cl-cc/runtime::%make-rt-green-thread :thunk (lambda () :x))))
    (cl-cc/runtime::rt-work-deque-push-front (cl-cc/runtime::rt-worker-deque w) task)
    ;; Steal via the work-stealing scheduler dispatch.
    (expect (cl-cc/runtime::rt-scheduler-steal ws) :to-be task)
    ;; And directly via a worker victim.
    (cl-cc/runtime::rt-work-deque-push-front (cl-cc/runtime::rt-worker-deque w) task)
    (expect (cl-cc/runtime::rt-scheduler-steal w) :to-be task)))

;;; ─── Thread pool (deterministic drain) ──────────────────────────────────────
(it-sequential
  "A pool's submitted tasks run when the pool scheduler is drained on this
thread."
  (let ((pool (cl-cc/runtime::rt-make-thread-pool :size 1))
        (n 0))
    (cl-cc/runtime::rt-thread-pool-submit
      pool
      (lambda ()
        (incf n)))
    (cl-cc/runtime::rt-thread-pool-submit
      pool
      (lambda ()
        (incf n)))
    (cl-cc/runtime::rt-thread-pool-run pool)
    (expect n :to-equal 2)))

(it-sequential
  "rt-thread-pool-start launches a worker OS thread that drains submitted work;
shutdown then lets it exit and be joined."
  (let ((pool (cl-cc/runtime::rt-make-thread-pool :size 1))
        (box (list nil)))
    (cl-cc/runtime::rt-thread-pool-submit
      pool
      (lambda ()
        (setf (first box) t)))
    (cl-cc/runtime::rt-thread-pool-start pool)
    (cl-weave:expect-poll
      (lambda ()
        (first box))
      (:timeout-ms 3000 :interval-ms 5)
      :to-be-truthy)
    (cl-cc/runtime::rt-thread-pool-shutdown pool)
    (dolist (th (cl-cc/runtime::rt-thread-pool-threads pool))
      (sb-thread:join-thread th))
    (expect (first box) :to-be-truthy)))

;;; ─── Native OS threads ──────────────────────────────────────────────────────
(it-sequential
  "rt-make-thread runs a real OS thread; rt-thread-join returns its result."
  (let ((th
        (cl-cc/runtime::rt-make-thread
          (lambda ()
            (+ 40 2)))))
    (expect (cl-cc/runtime::rt-thread-join th) :to-equal 42)
    (expect (cl-cc/runtime::rt-thread-alive-p th) :to-be-falsy)))

(it-sequential
  "A named native thread reports its name."
  (let ((th
        (cl-cc/runtime::rt-make-thread
          (lambda ()
            1)
          :name
          "namer")))
    (cl-cc/runtime::rt-thread-join th)
    (expect (cl-cc/runtime::rt-thread-name th) :to-equal "namer")))

(it-sequential
  "A native thread whose function errors ends :failed with the condition stored
on the wrapper (not re-signalled inside the worker, which would crash the
process in batch mode); rt-thread-join then re-signals it in the joiner."
  (let ((th
        (cl-cc/runtime::rt-make-thread
          (lambda ()
            (error "native boom")))))
    (signals error (cl-cc/runtime::rt-thread-join th))
    (expect (cl-cc/runtime::rt-native-thread-state th) :to-be :failed)
    (expect
      (typep (cl-cc/runtime::rt-native-thread-error th) (quote error))
      :to-be-truthy)))

(it-sequential
  "rt-make-thread requires an actual function."
  (signals type-error (cl-cc/runtime::rt-make-thread :not-a-fn)))

(it-sequential
  "rt-current-thread returns a wrapper; rt-all-threads includes at least it."
  (let ((cur (cl-cc/runtime::rt-current-thread)))
    (expect (typep cur (quote cl-cc/runtime::rt-native-thread)) :to-be-truthy)
    (expect (plusp (length (cl-cc/runtime::rt-all-threads))) :to-be-truthy)))

(it-sequential
  "rt-thread-yield yields the CPU and returns T."
  (expect (cl-cc/runtime::rt-thread-yield) :to-be-truthy))

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
