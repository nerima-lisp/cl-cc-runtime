;;;; scheduler-work-stealing.lisp — Work-stealing parallel task scheduler
;;;; (deques, workers, steal loop), split out of scheduler.lisp
(in-package :cl-cc/runtime)

(defstruct rt-work-deque
  "Per-worker deque used by the work-stealing scheduler.
Owner pushes/pops at the front; thieves steal from the back.  The mutex keeps
the implementation portable while preserving the CAS-style try/fail API shape."
  (items nil)
  (mutex (rt-make-mutex))
  (owner nil))

(defstruct rt-worker
  (id 0 :type integer)
  (scheduler nil)
  (deque (make-rt-work-deque))
  (thread nil)
  (running-p nil)
  (tasks-executed 0 :type integer)
  (steals 0 :type integer))

(defstruct rt-work-stealing-scheduler
  (workers nil)
  (next-worker 0 :type integer)
  (counter 0 :type integer)
  (mutex (rt-make-mutex))
  (shutdown-p nil)
  (min-workers 1 :type integer)
  (max-workers 1 :type integer))

(defun rt-work-deque-push-front (deque task)
  (rt-with-mutex ((rt-work-deque-mutex deque))
    (push task (rt-work-deque-items deque))
    task))

(defun rt-work-deque-pop-front (deque)
  (rt-with-mutex ((rt-work-deque-mutex deque))
    (pop (rt-work-deque-items deque))))

(defun rt-work-deque-steal-back (deque)
  "Attempt to steal one task from DEQUE. Returns NIL when empty or contended."
  (rt-with-try-mutex ((rt-work-deque-mutex deque))
    (let ((items (rt-work-deque-items deque)))
      (when items
        (if (endp (cdr items))
            (pop (rt-work-deque-items deque))
            (let* ((prev (last items 2))
                   (task (second prev)))
              (setf (cdr prev) nil)
              task))))))

(defun rt-work-deque-count (deque)
  (rt-with-mutex ((rt-work-deque-mutex deque))
    (length (rt-work-deque-items deque))))

(defun %rt-make-worker (scheduler id)
  (let* ((deque (make-rt-work-deque))
         (worker (make-rt-worker :id id :scheduler scheduler :deque deque)))
    (setf (rt-work-deque-owner deque) worker)
    worker))

(defun rt-make-work-stealing-scheduler (&key workers (min-workers 1) max-workers)
  "Create a work-stealing scheduler with per-worker deques."
  (let* ((detected (or workers 1))
         (max-count (max 1 (or max-workers detected)))
         (min-count (max 1 (min min-workers max-count)))
         (scheduler (make-rt-work-stealing-scheduler
                     :min-workers min-count
                     :max-workers max-count)))
    (dotimes (i (or workers min-count))
      (push (%rt-make-worker scheduler i)
            (rt-work-stealing-scheduler-workers scheduler)))
    (setf (rt-work-stealing-scheduler-workers scheduler)
          (nreverse (rt-work-stealing-scheduler-workers scheduler)))
    scheduler))

(defun rt-work-stealing-init (&key workers min-workers max-workers)
  (setf *rt-work-stealing-scheduler*
        (rt-make-work-stealing-scheduler :workers workers
                                         :min-workers (or min-workers 1)
                                         :max-workers max-workers)))

(defun %rt-ws-workers (scheduler)
  (or (rt-work-stealing-scheduler-workers scheduler)
      (setf (rt-work-stealing-scheduler-workers scheduler)
            (list (%rt-make-worker scheduler 0)))))

(defun %rt-ws-choose-worker (scheduler)
  (let* ((workers (%rt-ws-workers scheduler))
         (count (length workers))
         (index (mod (rt-work-stealing-scheduler-next-worker scheduler) count)))
    (incf (rt-work-stealing-scheduler-next-worker scheduler))
    (nth index workers)))

(defun rt-work-stealing-submit (scheduler thunk &key (priority :normal))
  "Submit THUNK to SCHEDULER. Returns an RT-GREEN-THREAD task object."
  (check-type thunk function)
  (let* ((worker (%rt-ws-choose-worker scheduler))
         (task (%make-rt-green-thread
                :id (incf (rt-work-stealing-scheduler-counter scheduler))
                :thunk thunk
                :priority priority)))
    (rt-work-deque-push-front (rt-worker-deque worker) task)
    task))

(defun %rt-worker-steal (worker)
  (let* ((scheduler (rt-worker-scheduler worker))
         (victims (remove worker (%rt-ws-workers scheduler) :test #'eq)))
    (loop for victim in victims
          for task = (rt-work-deque-steal-back (rt-worker-deque victim))
          when task
            do (incf (rt-worker-steals worker))
               (return task))))

(defun rt-worker-run-once (worker)
  "Run one task from WORKER's own deque, or steal from another worker."
  (let ((task (or (rt-work-deque-pop-front (rt-worker-deque worker))
                  (%rt-worker-steal worker))))
    (when task
      (%rt-run-green-thread task)
      (incf (rt-worker-tasks-executed worker)))
    task))

(defun rt-work-stealing-run (scheduler &key once)
  "Drain SCHEDULER cooperatively on the current OS thread."
  (loop
    with ran = nil
    do (setf ran nil)
       (dolist (worker (%rt-ws-workers scheduler))
         (when (rt-worker-run-once worker)
           (setf ran t)
           (when once (return-from rt-work-stealing-run t))))
       (unless ran (return nil))))

(defun rt-work-stealing-maybe-grow (scheduler)
  "Grow the worker set when all deques contain backlog and capacity remains."
  (rt-with-mutex ((rt-work-stealing-scheduler-mutex scheduler))
    (let ((workers (%rt-ws-workers scheduler)))
      (when (and (< (length workers) (rt-work-stealing-scheduler-max-workers scheduler))
                 (every (lambda (w) (> (rt-work-deque-count (rt-worker-deque w)) 0)) workers))
        (let ((worker (%rt-make-worker scheduler (length workers))))
          (setf (rt-work-stealing-scheduler-workers scheduler)
                (append workers (list worker)))
          worker)))))

(defun rt-scheduler-steal (victim)
  "Steal the lowest-priority available task from VICTIM scheduler."
  (etypecase victim
    (rt-scheduler
     (rt-with-mutex ((rt-scheduler-mutex victim))
       (loop for p in '(:low :normal :high)
             for q = (gethash p (rt-scheduler-priority-queues victim))
             when q do (return (pop (gethash p (rt-scheduler-priority-queues victim)))))))
    (rt-worker
     (rt-work-deque-steal-back (rt-worker-deque victim)))
    (rt-work-stealing-scheduler
     (loop for worker in (%rt-ws-workers victim)
           for task = (rt-work-deque-steal-back (rt-worker-deque worker))
           when task return task))))
