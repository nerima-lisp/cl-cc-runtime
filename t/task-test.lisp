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
(in-package :cl-cc-runtime/test)

(defun %make-terminal-task (&key (status :done) result error)
  "Build a green-thread task already in a terminal STATUS for wait-free tests."
  (cl-cc/runtime::%make-rt-green-thread
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
    (cl-cc/runtime::rt-task-cancel task)
    (expect (cl-cc/runtime::rt-task-cancelled-p task) :to-be-truthy)
    (expect (cl-cc/runtime::rt-green-thread-status task) :to-be :cancelled)))

(it-sequential
  "rt-task-result exposes result, error, and status."
  (let ((task (%make-terminal-task :status :done :result 99)))
    (multiple-value-bind (result error status) (cl-cc/runtime::rt-task-result task)
      (expect result :to-equal 99)
      (expect error :to-be-null)
      (expect status :to-be :done))))

;;; ─── Group membership & cancellation ────────────────────────────────────────
(it-sequential
  "rt-task-group-add pushes the task into the group's task list."
  (let ((group (cl-cc/runtime::make-rt-task-group))
        (task (%make-terminal-task)))
    (cl-cc/runtime::rt-task-group-add group task)
    (expect (member task (cl-cc/runtime::rt-task-group-tasks group)) :to-be-truthy)))

(it-sequential
  "Adding a task to an already-cancelled group immediately cancels it."
  (let ((group (cl-cc/runtime::make-rt-task-group))
        (task (%make-terminal-task :status :ready)))
    (setf (cl-cc/runtime::rt-task-group-cancelled-p group) t)
    (cl-cc/runtime::rt-task-group-add group task)
    (expect (cl-cc/runtime::rt-green-thread-status task) :to-be :cancelled)))

(it-sequential
  "rt-task-group-cancel cancels every member task and sets the cancelled flag."
  (let ((group (cl-cc/runtime::make-rt-task-group))
        (t1 (%make-terminal-task :status :ready))
        (t2 (%make-terminal-task :status :ready)))
    (cl-cc/runtime::rt-task-group-add group t1)
    (cl-cc/runtime::rt-task-group-add group t2)
    (cl-cc/runtime::rt-task-group-cancel group)
    (expect (cl-cc/runtime::rt-task-group-cancelled-p group) :to-be-truthy)
    (expect (cl-cc/runtime::rt-green-thread-status t1) :to-be :cancelled)
    (expect (cl-cc/runtime::rt-green-thread-status t2) :to-be :cancelled)))

;;; ─── Error collection ───────────────────────────────────────────────────────
(it-sequential
  "%rt-task-group-collect-errors records a failed task's error and cancels the
group."
  (let* ((group (cl-cc/runtime::make-rt-task-group))
         (err (make-condition 'simple-error :format-control "boom"))
         (task (%make-terminal-task :status :failed :error err)))
    (cl-cc/runtime::%rt-task-group-collect-errors group task)
    (expect (member err (cl-cc/runtime::rt-task-group-errors group)) :to-be-truthy)
    (expect (cl-cc/runtime::rt-task-group-cancelled-p group) :to-be-truthy)))

(it-sequential
  "A :done task contributes no error and does not cancel the group."
  (let ((group (cl-cc/runtime::make-rt-task-group))
        (task (%make-terminal-task :status :done :result 1)))
    (cl-cc/runtime::%rt-task-group-collect-errors group task)
    (expect (cl-cc/runtime::rt-task-group-errors group) :to-be-null)
    (expect (cl-cc/runtime::rt-task-group-cancelled-p group) :to-be-falsy)))

(it-sequential
  "rt-task-group-errors-list returns a fresh copy of the error list."
  (let ((group (cl-cc/runtime::make-rt-task-group)))
    (push :e1 (cl-cc/runtime::rt-task-group-errors group))
    (let ((copy (cl-cc/runtime::rt-task-group-errors-list group)))
      (expect copy :to-equal '(:e1))
      (expect (eq copy (cl-cc/runtime::rt-task-group-errors group)) :to-be-falsy))))

;;; ─── rt-task-group-wait on terminal tasks ───────────────────────────────────
(it-sequential
  "Waiting on a group whose tasks are already terminal returns the (empty)
error list without blocking."
  (let ((group (cl-cc/runtime::make-rt-task-group)))
    (cl-cc/runtime::rt-task-group-add group (%make-terminal-task :status :done))
    (cl-cc/runtime::rt-task-group-add group (%make-terminal-task :status :done))
    (expect (cl-cc/runtime::rt-task-group-wait group) :to-be-null)))

(it-sequential
  "Waiting surfaces a failed task's error into the group."
  (let* ((group (cl-cc/runtime::make-rt-task-group))
         (err (make-condition 'simple-error :format-control "x")))
    (cl-cc/runtime::rt-task-group-add
      group
      (%make-terminal-task :status :failed :error err))
    (let ((errors (cl-cc/runtime::rt-task-group-wait group)))
      (expect (member err errors) :to-be-truthy))))

;;; ─── rt-with-task-group macro ───────────────────────────────────────────────
(it-sequential
  "rt-with-task-group returns a group even when the body spawns nothing."
  (let ((group (cl-cc/runtime::rt-with-task-group () :nothing)))
    (expect (typep group (quote cl-cc/runtime::rt-task-group)) :to-be-truthy)
    (expect (cl-cc/runtime::rt-task-group-tasks group) :to-be-null)))

(it-sequential
  "An error signalled directly in the body is captured into the group's errors."
  (let ((group
        (cl-cc/runtime::rt-with-task-group (:cancel-on-error t) (error "body failure"))))
    (expect
      (find-if
        (lambda (e)
          (typep e 'error))
        (cl-cc/runtime::rt-task-group-errors group))
      :to-be-truthy)))

;;; ─── Scheduler-driven integration ───────────────────────────────────────────
(it-sequential "Green threads spawned inside rt-with-task-group auto-register with the group;
draining the scheduler inside the body lets the implicit wait complete." (cl-cc/runtime::rt-scheduler-init)
  (let ((counter 0))
    (let ((group (cl-cc/runtime::rt-with-task-group ()
                   (cl-cc/runtime::rt-spawn (lambda () (incf counter)))
                   (cl-cc/runtime::rt-spawn (lambda () (incf counter)))
                   (cl-cc/runtime::rt-scheduler-run))))
      (expect counter :to-equal 2)
      (expect (length (cl-cc/runtime::rt-task-group-tasks group)) :to-equal 2)
      ;; Both tasks ran to completion, so no errors were collected.
      (expect (cl-cc/runtime::rt-task-group-errors group) :to-be-null))))
