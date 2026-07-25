;;;; tests/task-tests.lisp
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

(in-suite cl-cc-unit-suite)

(defun %make-terminal-task (&key (status :done) result error)
  "Build a green-thread task already in a terminal STATUS for wait-free tests."
  (cl-cc/runtime::%make-rt-green-thread :status status :result result :error error))

;;; ─── Task cancellation & result ─────────────────────────────────────────────

(deftest task-cancel-sets-flags
  "rt-task-cancel marks the task cancelled and flips its status."
  (let ((task (%make-terminal-task :status :ready)))
    (cl-cc/runtime::rt-task-cancel task)
    (assert-true (cl-cc/runtime::rt-task-cancelled-p task))
    (assert-eq :cancelled (cl-cc/runtime::rt-green-thread-status task))))

(deftest task-result-returns-three-values
  "rt-task-result exposes result, error, and status."
  (let ((task (%make-terminal-task :status :done :result 99)))
    (multiple-value-bind (result error status) (cl-cc/runtime::rt-task-result task)
      (assert-= 99 result)
      (assert-null error)
      (assert-eq :done status))))

;;; ─── Group membership & cancellation ────────────────────────────────────────

(deftest task-group-add-registers-task
  "rt-task-group-add pushes the task into the group's task list."
  (let ((group (cl-cc/runtime::make-rt-task-group))
        (task (%make-terminal-task)))
    (cl-cc/runtime::rt-task-group-add group task)
    (assert-true (member task (cl-cc/runtime::rt-task-group-tasks group)))))

(deftest task-group-add-to-cancelled-group-cancels-task
  "Adding a task to an already-cancelled group immediately cancels it."
  (let ((group (cl-cc/runtime::make-rt-task-group))
        (task (%make-terminal-task :status :ready)))
    (setf (cl-cc/runtime::rt-task-group-cancelled-p group) t)
    (cl-cc/runtime::rt-task-group-add group task)
    (assert-eq :cancelled (cl-cc/runtime::rt-green-thread-status task))))

(deftest task-group-cancel-cancels-all-tasks
  "rt-task-group-cancel cancels every member task and sets the cancelled flag."
  (let ((group (cl-cc/runtime::make-rt-task-group))
        (t1 (%make-terminal-task :status :ready))
        (t2 (%make-terminal-task :status :ready)))
    (cl-cc/runtime::rt-task-group-add group t1)
    (cl-cc/runtime::rt-task-group-add group t2)
    (cl-cc/runtime::rt-task-group-cancel group)
    (assert-true (cl-cc/runtime::rt-task-group-cancelled-p group))
    (assert-eq :cancelled (cl-cc/runtime::rt-green-thread-status t1))
    (assert-eq :cancelled (cl-cc/runtime::rt-green-thread-status t2))))

;;; ─── Error collection ───────────────────────────────────────────────────────

(deftest task-group-collect-errors-from-failed-task
  "%rt-task-group-collect-errors records a failed task's error and cancels the
group."
  (let* ((group (cl-cc/runtime::make-rt-task-group))
         (err (make-condition 'simple-error :format-control "boom"))
         (task (%make-terminal-task :status :failed :error err)))
    (cl-cc/runtime::%rt-task-group-collect-errors group task)
    (assert-true (member err (cl-cc/runtime::rt-task-group-errors group)))
    (assert-true (cl-cc/runtime::rt-task-group-cancelled-p group))))

(deftest task-group-collect-errors-ignores-succeeded-task
  "A :done task contributes no error and does not cancel the group."
  (let ((group (cl-cc/runtime::make-rt-task-group))
        (task (%make-terminal-task :status :done :result 1)))
    (cl-cc/runtime::%rt-task-group-collect-errors group task)
    (assert-null (cl-cc/runtime::rt-task-group-errors group))
    (assert-false (cl-cc/runtime::rt-task-group-cancelled-p group))))

(deftest task-group-errors-list-returns-copy
  "rt-task-group-errors-list returns a fresh copy of the error list."
  (let ((group (cl-cc/runtime::make-rt-task-group)))
    (push :e1 (cl-cc/runtime::rt-task-group-errors group))
    (let ((copy (cl-cc/runtime::rt-task-group-errors-list group)))
      (assert-equal '(:e1) copy)
      (assert-false (eq copy (cl-cc/runtime::rt-task-group-errors group))))))

;;; ─── rt-task-group-wait on terminal tasks ───────────────────────────────────

(deftest task-group-wait-returns-with-terminal-tasks
  "Waiting on a group whose tasks are already terminal returns the (empty)
error list without blocking."
  (let ((group (cl-cc/runtime::make-rt-task-group)))
    (cl-cc/runtime::rt-task-group-add group (%make-terminal-task :status :done))
    (cl-cc/runtime::rt-task-group-add group (%make-terminal-task :status :done))
    (assert-null (cl-cc/runtime::rt-task-group-wait group))))

(deftest task-group-wait-collects-failed-task-error
  "Waiting surfaces a failed task's error into the group."
  (let* ((group (cl-cc/runtime::make-rt-task-group))
         (err (make-condition 'simple-error :format-control "x")))
    (cl-cc/runtime::rt-task-group-add group (%make-terminal-task :status :failed :error err))
    (let ((errors (cl-cc/runtime::rt-task-group-wait group)))
      (assert-true (member err errors)))))

;;; ─── rt-with-task-group macro ───────────────────────────────────────────────

(deftest task-with-group-empty-body
  "rt-with-task-group returns a group even when the body spawns nothing."
  (let ((group (cl-cc/runtime::rt-with-task-group () :nothing)))
    (assert-type cl-cc/runtime::rt-task-group group)
    (assert-null (cl-cc/runtime::rt-task-group-tasks group))))

(deftest task-with-group-body-error-recorded
  "An error signalled directly in the body is captured into the group's errors."
  (let ((group (cl-cc/runtime::rt-with-task-group (:cancel-on-error t)
                 (error "body failure"))))
    (assert-true (find-if (lambda (e) (typep e 'error))
                          (cl-cc/runtime::rt-task-group-errors group)))))

;;; ─── Scheduler-driven integration ───────────────────────────────────────────

(deftest task-with-group-spawned-threads-join-group
  "Green threads spawned inside rt-with-task-group auto-register with the group;
draining the scheduler inside the body lets the implicit wait complete."
  (cl-cc/runtime::rt-scheduler-init)
  (let ((counter 0))
    (let ((group (cl-cc/runtime::rt-with-task-group ()
                   (cl-cc/runtime::rt-spawn (lambda () (incf counter)))
                   (cl-cc/runtime::rt-spawn (lambda () (incf counter)))
                   (cl-cc/runtime::rt-scheduler-run))))
      (assert-= 2 counter)
      (assert-= 2 (length (cl-cc/runtime::rt-task-group-tasks group)))
      ;; Both tasks ran to completion, so no errors were collected.
      (assert-null (cl-cc/runtime::rt-task-group-errors group)))))
