;;;; tests/fiber-tests.lisp
;;;;
;;;; Tests for src/fiber.lisp — cooperative fibers resumed through a stored
;;;; continuation closure rather than an OS-thread stack.  Fibers are driven on
;;;; the current thread via the *rt-fiber-ready* queue, so these tests are
;;;; deterministic single-thread scheduling tests.  Each test rebinds
;;;; *rt-fiber-ready* to isolate the ready queue.

(in-package :cl-cc-runtime/test)

(in-suite cl-cc-unit-suite)

(defmacro with-clean-fibers (&body body)
  "Run BODY with an isolated, empty fiber ready queue."
  `(let ((cl-cc/runtime::*rt-fiber-ready* nil)
         (cl-cc/runtime::*rt-current-fiber* nil))
     ,@body))

;;; ─── Construction & scheduling ──────────────────────────────────────────────

(deftest fiber-make-assigns-id-and-ready-status
  "rt-make-fiber creates a fiber in :ready status with a fresh monotonic id."
  (with-clean-fibers
    (let* ((f1 (cl-cc/runtime::rt-make-fiber (lambda () 1)))
           (f2 (cl-cc/runtime::rt-make-fiber (lambda () 2))))
      (assert-eq :ready (cl-cc/runtime::rt-fiber-status f1))
      (assert-true (< (cl-cc/runtime::rt-fiber-id f1)
                      (cl-cc/runtime::rt-fiber-id f2))))))

(deftest fiber-schedule-pushes-to-ready-queue
  "rt-fiber-schedule enqueues the fiber and marks it :ready."
  (with-clean-fibers
    (let ((f (cl-cc/runtime::rt-make-fiber (lambda () :x))))
      (cl-cc/runtime::rt-fiber-schedule f)
      (assert-true (member f cl-cc/runtime::*rt-fiber-ready*))
      (assert-eq :ready (cl-cc/runtime::rt-fiber-status f)))))

(deftest fiber-spawn-schedules-new-fiber
  "rt-fiber-spawn builds and schedules a fiber in one step."
  (with-clean-fibers
    (let ((f (cl-cc/runtime::rt-fiber-spawn (lambda () :spawned))))
      (assert-true (member f cl-cc/runtime::*rt-fiber-ready*)))))

;;; ─── Resume: completion, result, failure ────────────────────────────────────

(deftest fiber-resume-runs-thunk-to-done
  "Resuming a ready fiber runs its thunk, captures the result, marks it :done."
  (with-clean-fibers
    (let ((f (cl-cc/runtime::rt-make-fiber (lambda () (+ 20 22)))))
      (assert-= 42 (cl-cc/runtime::rt-fiber-resume f))
      (assert-true (cl-cc/runtime::rt-fiber-done-p f))
      (assert-= 42 (cl-cc/runtime::rt-fiber-result f)))))

(deftest fiber-resume-error-marks-failed
  "A thunk that signals an error leaves the fiber :failed with the condition
recorded and rt-fiber-resume returning NIL."
  (with-clean-fibers
    (let ((f (cl-cc/runtime::rt-make-fiber (lambda () (error "boom")))))
      (assert-null (cl-cc/runtime::rt-fiber-resume f))
      (assert-true (cl-cc/runtime::rt-fiber-status-failed-p f))
      (assert-type error (cl-cc/runtime::rt-fiber-error f)))))

(deftest fiber-resume-terminal-returns-cached-result
  "Resuming an already-finished fiber is a no-op that returns the cached result."
  (with-clean-fibers
    (let ((f (cl-cc/runtime::rt-make-fiber (lambda () :done-once))))
      (cl-cc/runtime::rt-fiber-resume f)
      (assert-eq :done-once (cl-cc/runtime::rt-fiber-resume f)))))

(deftest fiber-resume-resolves-attached-future
  "When a fiber has an attached future, completing it resolves that future."
  (with-clean-fibers
    (let* ((fut (cl-cc/runtime::rt-make-future))
           (f (cl-cc/runtime::rt-make-fiber (lambda () :fiber-value) :future fut)))
      (cl-cc/runtime::rt-fiber-resume f)
      (assert-true (cl-cc/runtime::rt-future-done-p fut))
      (assert-eq :fiber-value (cl-cc/runtime::rt-future-await fut)))))

(deftest fiber-resume-failure-resolves-future-with-condition
  "A failing fiber resolves its future with the signalled condition."
  (with-clean-fibers
    (let* ((fut (cl-cc/runtime::rt-make-future))
           (f (cl-cc/runtime::rt-make-fiber (lambda () (error "kaboom")) :future fut)))
      (cl-cc/runtime::rt-fiber-resume f)
      (assert-type error (cl-cc/runtime::rt-future-await fut)))))

;;; ─── Continuations: set-continuation, block, resume ─────────────────────────

(deftest fiber-set-continuation-suspends
  "rt-fiber-set-continuation installs the next step and marks the fiber
:suspended; a later resume runs that continuation."
  (with-clean-fibers
    (let ((f (cl-cc/runtime::rt-make-fiber (lambda () :never-run-thunk))))
      (cl-cc/runtime::rt-fiber-set-continuation f (lambda () :resumed-step))
      (assert-eq :suspended (cl-cc/runtime::rt-fiber-status f))
      (assert-eq :resumed-step (cl-cc/runtime::rt-fiber-resume f))
      (assert-true (cl-cc/runtime::rt-fiber-done-p f)))))

(deftest fiber-set-continuation-type-checks
  "rt-fiber-set-continuation requires a fiber and a function."
  (with-clean-fibers
    (let ((f (cl-cc/runtime::rt-make-fiber (lambda () :x))))
      (assert-signals type-error (cl-cc/runtime::rt-fiber-set-continuation f :not-a-fn)))))

(deftest fiber-yield-reschedules-current-fiber
  "Calling rt-fiber-yield from inside a running fiber records the yielded value
and re-schedules the fiber as :ready."
  (with-clean-fibers
    (let ((f (cl-cc/runtime::rt-make-fiber
              (lambda () (cl-cc/runtime::rt-fiber-yield :paused)))))
      (cl-cc/runtime::rt-fiber-resume f)
      ;; yield set status back to :ready and pushed the fiber onto the queue.
      (assert-eq :ready (cl-cc/runtime::rt-fiber-status f))
      (assert-eq :paused (cl-cc/runtime::rt-fiber-yielded-value f))
      (assert-true (member f cl-cc/runtime::*rt-fiber-ready*)))))

(deftest fiber-yield-outside-fiber-is-identity
  "Outside any fiber, rt-fiber-yield simply returns its argument."
  (with-clean-fibers
    (assert-eq :val (cl-cc/runtime::rt-fiber-yield :val))))

;;; ─── Fiber-locals ───────────────────────────────────────────────────────────

(deftest fiber-locals-get-set-within-fiber
  "rt-fiber-local reads and writes per-fiber storage while the fiber runs."
  (with-clean-fibers
    (let ((f (cl-cc/runtime::rt-make-fiber
              (lambda ()
                (setf (cl-cc/runtime::rt-fiber-local :k) :stored)
                (cl-cc/runtime::rt-fiber-local :k)))))
      (assert-eq :stored (cl-cc/runtime::rt-fiber-resume f)))))

(deftest fiber-local-default-outside-fiber
  "Outside a fiber rt-fiber-local returns the default and setf errors."
  (with-clean-fibers
    (assert-eq :dflt (cl-cc/runtime::rt-fiber-local :missing :dflt))
    (assert-signals error (setf (cl-cc/runtime::rt-fiber-local :k) 1))))

;;; ─── Running the ready queue ────────────────────────────────────────────────

(deftest fiber-run-fibers-drains-queue
  "rt-run-fibers resumes every ready fiber until the queue empties."
  (with-clean-fibers
    (let ((log nil))
      (dolist (i '(1 2 3))
        (cl-cc/runtime::rt-fiber-spawn (let ((i i)) (lambda () (push i log)))))
      (cl-cc/runtime::rt-run-fibers)
      (assert-null cl-cc/runtime::*rt-fiber-ready*)
      (assert-equal '(1 2 3) (sort log #'<)))))

(deftest fiber-run-fibers-once-returns-single
  "rt-run-fibers with :once resumes exactly one fiber and returns it."
  (with-clean-fibers
    (let ((ran nil))
      (cl-cc/runtime::rt-fiber-spawn (lambda () (push :a ran)))
      (cl-cc/runtime::rt-fiber-spawn (lambda () (push :b ran)))
      (let ((f (cl-cc/runtime::rt-run-fibers :once t)))
        (assert-true (cl-cc/runtime::rt-fiber-p f))
        (assert-= 1 (length ran))
        ;; One fiber remains queued.
        (assert-= 1 (length cl-cc/runtime::*rt-fiber-ready*))))))

;;; ─── rt-fiber-async: fiber + future ─────────────────────────────────────────

(deftest fiber-async-returns-resolving-future
  "rt-fiber-async spawns a fiber and returns a future resolved once the fiber
is run."
  (with-clean-fibers
    (let ((fut (cl-cc/runtime::rt-fiber-async (lambda () :async-result))))
      (assert-false (cl-cc/runtime::rt-future-done-p fut))
      (cl-cc/runtime::rt-run-fibers)
      (assert-true (cl-cc/runtime::rt-future-done-p fut))
      (assert-eq :async-result (cl-cc/runtime::rt-future-await fut)))))

(deftest fiber-await-already-done-future
  "rt-fiber-await on an already-resolved future returns its value directly."
  (with-clean-fibers
    (let ((fut (cl-cc/runtime::rt-make-future)))
      (cl-cc/runtime::rt-future-resolve fut :ready)
      (assert-eq :ready (cl-cc/runtime::rt-fiber-await fut)))))

;;; ─── Green-thread dispatch fallback ─────────────────────────────────────────

(deftest fiber-green-thread-spawn-fiber-fallback
  "With neither a work-stealing nor a global scheduler bound, rt-green-thread-spawn
falls back to spawning a fiber."
  (with-clean-fibers
    (let ((cl-cc/runtime::*rt-work-stealing-scheduler* nil)
          (cl-cc/runtime::*rt-global-scheduler* nil))
      (let ((f (cl-cc/runtime::rt-green-thread-spawn (lambda () :gt) :scheduler nil)))
        (assert-true (cl-cc/runtime::rt-fiber-p f))
        (assert-true (member f cl-cc/runtime::*rt-fiber-ready*))))))

(deftest fiber-run-green-threads-fiber-fallback
  "rt-run-green-threads drains the fiber queue when no scheduler is bound."
  (with-clean-fibers
    (let ((cl-cc/runtime::*rt-work-stealing-scheduler* nil)
          (cl-cc/runtime::*rt-global-scheduler* nil)
          (ran nil))
      (cl-cc/runtime::rt-fiber-spawn (lambda () (setf ran t)))
      (cl-cc/runtime::rt-run-green-threads)
      (assert-true ran))))

;;; ─── Property: a fiber returning n resumes to exactly n ──────────────────────

(cl-weave:it-property "fiber result equals its thunk's return value"
    ((n (cl-weave:gen-integer :min -500 :max 500)))
  (let ((cl-cc/runtime::*rt-fiber-ready* nil)
        (cl-cc/runtime::*rt-current-fiber* nil))
    (let ((f (cl-cc/runtime::rt-make-fiber (lambda () n))))
      (cl-cc/runtime::rt-fiber-resume f)
      (and (cl-cc/runtime::rt-fiber-done-p f)
           (eql n (cl-cc/runtime::rt-fiber-result f))))))
