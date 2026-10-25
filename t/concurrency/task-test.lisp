;;;; t/task-test.lisp
;;;;
;;;; Tests for src/task.lisp — structured concurrency / task groups over
;;;; rt-green-thread tasks.  Covers cancellation, error collection from failed
;;;; tasks, the rt-with-task-group macro (including cancel-on-error), and a
;;;; scheduler-driven integration where spawned green threads join their
;;;; enclosing group automatically.
;;;;
;;;; rt-task-group-wait polls until each task leaves the (:ready :running
;;;; :sleeping) set, so unit tests use tasks already in a terminal state to stay
;;;; deterministic; the integration test drains the cooperative scheduler inside
;;;; the group body before the implicit wait runs.
(in-package :cl-cc/runtime/concurrency/test)

(defun %make-terminal-task (&key (status :done) result error)
  "Build a green-thread task already in a terminal STATUS for wait-free tests."
  (%make-rt-green-thread
    :status
    status
    :result
    result
    :error
    error))

;;; ─── Task cancellation & result ─────────────────────────────────────────────
(it-sequential
  "rt-task-cancel marks the task cancelled and flips its status."
  (let ((task (%make-terminal-task :status :ready)))
    (rt-task-cancel task)
    (expect (rt-task-cancelled-p task) :to-be-truthy)
    (expect (cl-cc/runtime/concurrency:rt-green-thread-status task) :to-be :cancelled)))

(it-sequential
  "rt-task-result exposes result, error, and status."
  (let ((task (%make-terminal-task :status :done :result 99)))
    (multiple-value-bind (result error status) (rt-task-result task)
      (expect result :to-equal 99)
      (expect error :to-be-null)
      (expect status :to-be :done))))

;;; ─── Group membership & cancellation ────────────────────────────────────────
(it-sequential
  "rt-task-group-add pushes the task into the group's task list."
  (let ((group (make-rt-task-group))
        (task (%make-terminal-task)))
    (rt-task-group-add group task)
    (expect (member task (rt-task-group-tasks group)) :to-be-truthy)))

(it-sequential
  "Adding a task to an already-cancelled group immediately cancels it."
  (let ((group (make-rt-task-group))
        (task (%make-terminal-task :status :ready)))
    (setf (rt-task-group-cancelled-p group) t)
    (rt-task-group-add group task)
    (expect (cl-cc/runtime/concurrency:rt-green-thread-status task) :to-be :cancelled)))

(it-sequential
  "rt-task-group-cancel cancels every member task and sets the cancelled flag."
  (let ((group (make-rt-task-group))
        (t1 (%make-terminal-task :status :ready))
        (t2 (%make-terminal-task :status :ready)))
    (rt-task-group-add group t1)
    (rt-task-group-add group t2)
    (rt-task-group-cancel group)
    (expect (rt-task-group-cancelled-p group) :to-be-truthy)
    (expect (cl-cc/runtime/concurrency:rt-green-thread-status t1) :to-be :cancelled)
    (expect (cl-cc/runtime/concurrency:rt-green-thread-status t2) :to-be :cancelled)))

;;; ─── Error collection ───────────────────────────────────────────────────────
(it-sequential
  "%rt-task-group-collect-errors records a failed task's error and cancels the
group."
  (let* ((group (make-rt-task-group))
         (err (make-condition 'simple-error :format-control "boom"))
         (task (%make-terminal-task :status :failed :error err)))
    (%rt-task-group-collect-errors group task)
    (expect (member err (rt-task-group-errors group)) :to-be-truthy)
    (expect (rt-task-group-cancelled-p group) :to-be-truthy)))

(it-sequential
  "A :done task contributes no error and does not cancel the group."
  (let ((group (make-rt-task-group))
        (task (%make-terminal-task :status :done :result 1)))
    (%rt-task-group-collect-errors group task)
    (expect (rt-task-group-errors group) :to-be-null)
    (expect (rt-task-group-cancelled-p group) :to-be-falsy)))

(it-sequential
  "rt-task-group-errors-list returns a fresh copy of the error list."
  (let ((group (make-rt-task-group)))
    (push :e1 (rt-task-group-errors group))
    (let ((copy (rt-task-group-errors-list group)))
      (expect copy :to-equal '(:e1))
      (expect (eq copy (rt-task-group-errors group)) :to-be-falsy))))

;;; ─── rt-task-group-wait on terminal tasks ───────────────────────────────────
(it-sequential
  "Waiting on a group whose tasks are already terminal returns the (empty)
error list without blocking."
  (let ((group (make-rt-task-group)))
    (rt-task-group-add group (%make-terminal-task :status :done))
    (rt-task-group-add group (%make-terminal-task :status :done))
    (expect (rt-task-group-wait group) :to-be-null)))

(it-sequential
  "Waiting surfaces a failed task's error into the group."
  (let* ((group (make-rt-task-group))
         (err (make-condition 'simple-error :format-control "x")))
    (rt-task-group-add
      group
      (%make-terminal-task :status :failed :error err))
    (let ((errors (rt-task-group-wait group)))
      (expect (member err errors) :to-be-truthy))))

;;; ─── rt-with-task-group macro ───────────────────────────────────────────────
(it-sequential
  "rt-with-task-group returns a group even when the body spawns nothing."
  (let ((group (rt-with-task-group () :nothing)))
    (expect (typep group (quote rt-task-group)) :to-be-truthy)
    (expect (rt-task-group-tasks group) :to-be-null)))

(it-sequential
  "An error signalled directly in the body is captured into the group's errors."
  (let ((group
        (rt-with-task-group (:cancel-on-error t) (error "body failure"))))
    (expect
      (find-if
        (lambda (e)
          (typep e 'error))
        (rt-task-group-errors group))
      :to-be-truthy)))

;;; ─── Scheduler-driven integration ───────────────────────────────────────────
(it-sequential "Green threads spawned inside rt-with-task-group auto-register with the group;
draining the scheduler inside the body lets the implicit wait complete." (cl-cc/runtime/concurrency:rt-scheduler-init)
  (let ((counter 0))
    (let ((group (rt-with-task-group ()
                   (cl-cc/runtime/concurrency:rt-spawn (lambda () (incf counter)))
                   (cl-cc/runtime/concurrency:rt-spawn (lambda () (incf counter)))
                   (cl-cc/runtime/concurrency:rt-scheduler-run))))
      (expect counter :to-equal 2)
      (expect (length (rt-task-group-tasks group)) :to-equal 2)
      ;; Both tasks ran to completion, so no errors were collected.
      (expect (rt-task-group-errors group) :to-be-null))))
