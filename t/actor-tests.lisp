;;;; t/actor-tests.lisp
;;;;
;;;; Tests for src/actor.lisp — an Erlang-style actor model: registry, mailbox
;;;; send/receive backed by a real mutex + condition variable, links/monitors,
;;;; supervisor restart strategies.
;;;;
;;;; NOTE ON MAILBOX ORDER: rt-actor-send PUSHes onto the mailbox head and
;;;; rt-actor-receive POPs the head, so the mailbox is LIFO, not FIFO.  The
;;;; ordering tests below assert this actual behavior rather than an assumed
;;;; FIFO contract (the docstrings do not promise an order).

(in-package :cl-cc-runtime/test)

(in-suite cl-cc-unit-suite)

(defmacro with-clean-registry (&body body)
  "Run BODY with the actor registry cleared before and after."
  `(progn
     (cl-cc/runtime::rt-actor-clear-registry)
     (unwind-protect (progn ,@body)
       (cl-cc/runtime::rt-actor-clear-registry))))

;;; ─── Construction & registry ────────────────────────────────────────────────

(deftest actor-make-defaults-created-status
  "A new actor starts in :created status with an empty mailbox."
  (let ((a (cl-cc/runtime::rt-make-actor nil)))
    (assert-eq :created (cl-cc/runtime::rt-actor-status a))
    (assert-null (cl-cc/runtime::rt-actor-mailbox a))))

(deftest actor-make-with-name-registers
  "Naming an actor at creation registers it for whereis lookup."
  (with-clean-registry
    (let ((a (cl-cc/runtime::rt-make-actor nil :name :worker)))
      (assert-eq a (cl-cc/runtime::rt-actor-whereis :worker)))))

(deftest actor-register-and-unregister
  "rt-actor-register/unregister add and remove name bindings."
  (with-clean-registry
    (let ((a (cl-cc/runtime::rt-make-actor nil)))
      (cl-cc/runtime::rt-actor-register :svc a)
      (assert-eq a (cl-cc/runtime::rt-actor-whereis :svc))
      (assert-eq :svc (cl-cc/runtime::rt-actor-name a))
      (cl-cc/runtime::rt-actor-unregister :svc)
      (assert-null (cl-cc/runtime::rt-actor-whereis :svc)))))

(deftest actor-clear-registry-empties-all
  "rt-actor-clear-registry removes every registered name."
  (with-clean-registry
    (cl-cc/runtime::rt-make-actor nil :name :a)
    (cl-cc/runtime::rt-make-actor nil :name :b)
    (cl-cc/runtime::rt-actor-clear-registry)
    (assert-null (cl-cc/runtime::rt-actor-whereis :a))
    (assert-null (cl-cc/runtime::rt-actor-whereis :b))))

;;; ─── send / receive ─────────────────────────────────────────────────────────

(deftest actor-send-receive-single
  "A single sent message is delivered by receive without blocking."
  (let ((a (cl-cc/runtime::rt-make-actor nil)))
    (cl-cc/runtime::rt-actor-send a :ping)
    (assert-eq :ping (cl-cc/runtime::rt-actor-receive a :timeout 0.1))))

(deftest actor-receive-is-lifo
  "With messages already queued, receive returns them last-in-first-out."
  (let ((a (cl-cc/runtime::rt-make-actor nil)))
    (cl-cc/runtime::rt-actor-send a 1)
    (cl-cc/runtime::rt-actor-send a 2)
    (cl-cc/runtime::rt-actor-send a 3)
    (assert-= 3 (cl-cc/runtime::rt-actor-receive a :timeout 0.1))
    (assert-= 2 (cl-cc/runtime::rt-actor-receive a :timeout 0.1))
    (assert-= 1 (cl-cc/runtime::rt-actor-receive a :timeout 0.1))))

(deftest actor-receive-stopped-empty-returns-nil
  "Receiving from a stopped, empty actor returns NIL rather than blocking."
  (let ((a (cl-cc/runtime::rt-make-actor nil)))
    (cl-cc/runtime::rt-actor-stop a)
    (assert-null (cl-cc/runtime::rt-actor-receive a :timeout 0.1))))

;;; ─── Links & monitors ───────────────────────────────────────────────────────

(deftest actor-link-is-mutual
  "rt-actor-link records each actor in the other's link list."
  (let ((a (cl-cc/runtime::rt-make-actor nil))
        (b (cl-cc/runtime::rt-make-actor nil)))
    (cl-cc/runtime::rt-actor-link a b)
    (assert-true (member b (cl-cc/runtime::rt-actor-links a)))
    (assert-true (member a (cl-cc/runtime::rt-actor-links b)))))

(deftest actor-monitor-adds-watcher
  "rt-actor-monitor adds the watcher to the target's monitor list."
  (let ((watcher (cl-cc/runtime::rt-make-actor nil))
        (target (cl-cc/runtime::rt-make-actor nil)))
    (cl-cc/runtime::rt-actor-monitor watcher target)
    (assert-true (member watcher (cl-cc/runtime::rt-actor-monitors target)))))

(deftest actor-stop-notifies-linked-and-monitoring
  "Stopping an actor delivers an :exit message to links and a :down message to
monitors, each carrying the stopped actor and the reason."
  (let ((a (cl-cc/runtime::rt-make-actor nil))
        (linked (cl-cc/runtime::rt-make-actor nil))
        (watcher (cl-cc/runtime::rt-make-actor nil)))
    (cl-cc/runtime::rt-actor-link a linked)
    (cl-cc/runtime::rt-actor-monitor watcher a)
    (cl-cc/runtime::rt-actor-stop a :shutdown)
    (assert-eq :stopped (cl-cc/runtime::rt-actor-status a))
    (let ((exit-msg (cl-cc/runtime::rt-actor-receive linked :timeout 0.1)))
      (assert-equal (list :exit a :shutdown) exit-msg))
    (let ((down-msg (cl-cc/runtime::rt-actor-receive watcher :timeout 0.1)))
      (assert-equal (list :down a :shutdown) down-msg))))

;;; ─── Supervisor ─────────────────────────────────────────────────────────────

(deftest actor-supervisor-registers-children
  "Creating an actor under a supervisor records it as a child."
  (let* ((sup (cl-cc/runtime::rt-make-supervisor :strategy :one-for-one))
         (child (cl-cc/runtime::rt-make-actor nil :supervisor sup)))
    (assert-true (member child (cl-cc/runtime::rt-supervisor-children sup)))
    (assert-eq :one-for-one (cl-cc/runtime::rt-supervisor-strategy sup))))

(deftest actor-supervisor-restart-increments-count
  "A one-for-one supervisor restart re-spawns the actor and bumps the counter."
  (cl-cc/runtime::rt-scheduler-init)
  (let* ((sup (cl-cc/runtime::rt-make-supervisor :strategy :one-for-one))
         (child (cl-cc/runtime::rt-make-actor
                 (lambda (m) (declare (ignore m))) :supervisor sup)))
    (cl-cc/runtime::%rt-supervisor-restart sup child)
    (assert-= 1 (cl-cc/runtime::rt-supervisor-restarts sup))
    ;; The restart routed through rt-actor-spawn, which marks it running.
    (assert-eq :running (cl-cc/runtime::rt-actor-status child))))

(deftest actor-spawn-marks-running-with-task
  "rt-actor-spawn sets the actor running and installs a scheduler task
(without the test draining the cooperative scheduler)."
  (cl-cc/runtime::rt-scheduler-init)
  (let ((a (cl-cc/runtime::rt-make-actor (lambda (m) (declare (ignore m))))))
    (cl-cc/runtime::rt-actor-spawn a)
    (assert-eq :running (cl-cc/runtime::rt-actor-status a))
    (assert-true (cl-cc/runtime::rt-actor-task a))))

;;; ─── Genuine concurrent mailbox delivery ────────────────────────────────────

(deftest actor-concurrent-receive-loop
  "A receive loop running on its own OS thread drains messages sent from the
main thread; stopping the actor terminates the loop.  All sent messages are
delivered (order is LIFO, so we compare as a set)."
  (let* ((a (cl-cc/runtime::rt-make-actor nil))
         (n 15)
         (got nil)
         (receiver
           (sb-thread:make-thread
            (lambda ()
              (loop for msg = (cl-cc/runtime::rt-actor-receive a)
                    while msg do (push msg got)))
            :name "actor-receiver")))
    (dotimes (i n) (cl-cc/runtime::rt-actor-send a i))
    ;; Let the receiver drain the mailbox before stopping.
    (loop repeat 200
          until (= (length got) n)
          do (sleep 0.005))
    (cl-cc/runtime::rt-actor-stop a)
    (sb-thread:join-thread receiver)
    (assert-equal (loop for i below n collect i) (sort (copy-list got) #'<))))
