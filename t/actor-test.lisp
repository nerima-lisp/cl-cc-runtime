;;;; t/actor-test.lisp
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

(defmacro with-clean-registry (&body body)
  "Run BODY with the actor registry cleared before and after."
  `(progn
    (cl-cc/runtime::rt-actor-clear-registry)
    (unwind-protect (progn
        ,@body)
      (cl-cc/runtime::rt-actor-clear-registry))))

;;; ─── Construction & registry ────────────────────────────────────────────────
(it-sequential
  "A new actor starts in :created status with an empty mailbox."
  (let ((a (cl-cc/runtime::rt-make-actor nil)))
    (expect (cl-cc/runtime::rt-actor-status a) :to-be :created)
    (expect (cl-cc/runtime::rt-actor-mailbox a) :to-be-null)))

(it-sequential
  "Naming an actor at creation registers it for whereis lookup."
  (with-clean-registry
    (let ((a (cl-cc/runtime::rt-make-actor nil :name :worker)))
      (expect (cl-cc/runtime::rt-actor-whereis :worker) :to-be a))))

(it-sequential
  "rt-actor-register/unregister add and remove name bindings."
  (with-clean-registry
    (let ((a (cl-cc/runtime::rt-make-actor nil)))
      (cl-cc/runtime::rt-actor-register :svc a)
      (expect (cl-cc/runtime::rt-actor-whereis :svc) :to-be a)
      (expect (cl-cc/runtime::rt-actor-name a) :to-be :svc)
      (cl-cc/runtime::rt-actor-unregister :svc)
      (expect (cl-cc/runtime::rt-actor-whereis :svc) :to-be-null))))

(it-sequential
  "rt-actor-clear-registry removes every registered name."
  (with-clean-registry
    (cl-cc/runtime::rt-make-actor nil :name :a)
    (cl-cc/runtime::rt-make-actor nil :name :b)
    (cl-cc/runtime::rt-actor-clear-registry)
    (expect (cl-cc/runtime::rt-actor-whereis :a) :to-be-null)
    (expect (cl-cc/runtime::rt-actor-whereis :b) :to-be-null)))

;;; ─── send / receive ─────────────────────────────────────────────────────────
(it-sequential
  "A single sent message is delivered by receive without blocking."
  (let ((a (cl-cc/runtime::rt-make-actor nil)))
    (cl-cc/runtime::rt-actor-send a :ping)
    (expect (cl-cc/runtime::rt-actor-receive a :timeout 0.1) :to-be :ping)))

(it-sequential
  "With messages already queued, receive returns them last-in-first-out."
  (let ((a (cl-cc/runtime::rt-make-actor nil)))
    (cl-cc/runtime::rt-actor-send a 1)
    (cl-cc/runtime::rt-actor-send a 2)
    (cl-cc/runtime::rt-actor-send a 3)
    (expect (cl-cc/runtime::rt-actor-receive a :timeout 0.1) :to-equal 3)
    (expect (cl-cc/runtime::rt-actor-receive a :timeout 0.1) :to-equal 2)
    (expect (cl-cc/runtime::rt-actor-receive a :timeout 0.1) :to-equal 1)))

;;; ─── Mailbox backpressure ───────────────────────────────────────────────────
;;; RT-ACTOR-SEND used to have no mailbox capacity limit at all: a producer
;;; faster than its consumer grew the mailbox without bound. MAILBOX-LIMIT
;;; is opt-in (default NIL preserves the original unbounded mailbox) so
;;; existing callers are unaffected.
(it-sequential
  "without a MAILBOX-LIMIT, the mailbox still grows without bound"
  (let ((a (cl-cc/runtime::rt-make-actor nil)))
    (dotimes (i 50) (cl-cc/runtime::rt-actor-send a i))
    (expect (length (cl-cc/runtime::rt-actor-mailbox a)) :to-be 50)))
(it-sequential
  "with MAILBOX-LIMIT, a send that fits succeeds immediately"
  (let ((a (cl-cc/runtime::rt-make-actor nil :mailbox-limit 2)))
    (expect (cl-cc/runtime::rt-actor-send a :one) :to-be :one)
    (expect (cl-cc/runtime::rt-actor-send a :two) :to-be :two)
    (expect (length (cl-cc/runtime::rt-actor-mailbox a)) :to-be 2)))
(it-sequential
  "with MAILBOX-LIMIT full and no TIMEOUT-bound receiver, send gives up promptly rather than blocking forever"
  (let ((a (cl-cc/runtime::rt-make-actor nil :mailbox-limit 1))
        (started (get-internal-real-time)))
    (cl-cc/runtime::rt-actor-send a :fills-the-only-slot)
    (expect (cl-cc/runtime::rt-actor-send a :never-fits :timeout 0.05) :to-be-null)
    (expect
      (< (- (get-internal-real-time) started) internal-time-units-per-second)
      :to-be-truthy)))
(it-sequential
  "with MAILBOX-LIMIT full, a send blocks until a receiver drains room and then succeeds"
  (let* ((a (cl-cc/runtime::rt-make-actor nil :mailbox-limit 1))
         (sent-second nil))
    (cl-cc/runtime::rt-actor-send a :first)
    (let ((sender
          (sb-thread:make-thread
            (lambda ()
              (setf sent-second (cl-cc/runtime::rt-actor-send a :second :timeout 1.0))))))
      (sleep 0.05) ; let the sender reach the blocking wait for mailbox room
      (expect (cl-cc/runtime::rt-actor-receive a :timeout 1.0) :to-equal :first)
      (sb-thread:join-thread sender))
    (expect sent-second :to-be :second)))

(it-sequential
  "Receiving from a stopped, empty actor returns NIL rather than blocking."
  (let ((a (cl-cc/runtime::rt-make-actor nil)))
    (cl-cc/runtime::rt-actor-stop a)
    (expect (cl-cc/runtime::rt-actor-receive a :timeout 0.1) :to-be-null)))

;;; ─── Links & monitors ───────────────────────────────────────────────────────
(it-sequential
  "rt-actor-link records each actor in the other's link list."
  (let ((a (cl-cc/runtime::rt-make-actor nil))
        (b (cl-cc/runtime::rt-make-actor nil)))
    (cl-cc/runtime::rt-actor-link a b)
    (expect (member b (cl-cc/runtime::rt-actor-links a)) :to-be-truthy)
    (expect (member a (cl-cc/runtime::rt-actor-links b)) :to-be-truthy)))

(it-sequential
  "rt-actor-monitor adds the watcher to the target's monitor list."
  (let ((watcher (cl-cc/runtime::rt-make-actor nil))
        (target (cl-cc/runtime::rt-make-actor nil)))
    (cl-cc/runtime::rt-actor-monitor watcher target)
    (expect
      (member watcher (cl-cc/runtime::rt-actor-monitors target))
      :to-be-truthy)))

(it-sequential
  "Stopping an actor delivers an :exit message to links and a :down message to
monitors, each carrying the stopped actor and the reason."
  (let ((a (cl-cc/runtime::rt-make-actor nil))
        (linked (cl-cc/runtime::rt-make-actor nil))
        (watcher (cl-cc/runtime::rt-make-actor nil)))
    (cl-cc/runtime::rt-actor-link a linked)
    (cl-cc/runtime::rt-actor-monitor watcher a)
    (cl-cc/runtime::rt-actor-stop a :shutdown)
    (expect (cl-cc/runtime::rt-actor-status a) :to-be :stopped)
    (let ((exit-msg (cl-cc/runtime::rt-actor-receive linked :timeout 0.1)))
      (expect exit-msg :to-equal (list :exit a :shutdown)))
    (let ((down-msg (cl-cc/runtime::rt-actor-receive watcher :timeout 0.1)))
      (expect down-msg :to-equal (list :down a :shutdown)))))

;;; ─── Supervisor ─────────────────────────────────────────────────────────────
(it-sequential
  "Creating an actor under a supervisor records it as a child."
  (let* ((sup (cl-cc/runtime::rt-make-supervisor :strategy :one-for-one))
         (child (cl-cc/runtime::rt-make-actor nil :supervisor sup)))
    (expect
      (member child (cl-cc/runtime::rt-supervisor-children sup))
      :to-be-truthy)
    (expect (cl-cc/runtime::rt-supervisor-strategy sup) :to-be :one-for-one)))

(it-sequential "A one-for-one supervisor restart re-spawns the actor and bumps the counter." (cl-cc/runtime::rt-scheduler-init)
  (let* ((sup (cl-cc/runtime::rt-make-supervisor :strategy :one-for-one))
         (child (cl-cc/runtime::rt-make-actor
                 (lambda (m) (declare (ignore m))) :supervisor sup)))
    (cl-cc/runtime::%rt-supervisor-restart sup child)
    (expect (cl-cc/runtime::rt-supervisor-restarts sup) :to-equal 1)
    ;; The restart routed through rt-actor-spawn, which marks it running.
    (expect (cl-cc/runtime::rt-actor-status child) :to-be :running)))

(it-sequential
  "rt-actor-spawn sets the actor running and installs a scheduler task
(without the test draining the cooperative scheduler)."
  (cl-cc/runtime::rt-scheduler-init)
  (let ((a
        (cl-cc/runtime::rt-make-actor
          (lambda (m)
            (declare (ignore m))))))
    (cl-cc/runtime::rt-actor-spawn a)
    (expect (cl-cc/runtime::rt-actor-status a) :to-be :running)
    (expect (cl-cc/runtime::rt-actor-task a) :to-be-truthy)))

;;; ─── Genuine concurrent mailbox delivery ────────────────────────────────────
(it-sequential "A receive loop running on its own OS thread drains messages sent from the
main thread; stopping the actor terminates the loop.  All sent messages are
delivered (order is LIFO, so we compare as a set)." (let* ((a (cl-cc/runtime::rt-make-actor nil))
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
    (expect (sort (copy-list got) #'<) :to-equal (loop for i below n collect i))))
