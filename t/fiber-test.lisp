;;;; t/fiber-test.lisp
;;;;
;;;; Tests for src/fiber.lisp — cooperative fibers resumed through a stored
;;;; continuation closure rather than an OS-thread stack.  Fibers are driven on
;;;; the current thread via the *rt-fiber-ready* queue, so these tests are
;;;; deterministic single-thread scheduling tests.  Each test rebinds
;;;; *rt-fiber-ready* to isolate the ready queue.
(in-package :cl-cc-runtime/test)

(defmacro with-clean-fibers (&body body)
  "Run BODY with an isolated, empty fiber ready queue."
  `(let ((cl-cc/runtime::*rt-fiber-ready* nil)
        (cl-cc/runtime::*rt-current-fiber* nil))
    ,@body))

;;; ─── Construction & scheduling ──────────────────────────────────────────────
(it-sequential
  "rt-make-fiber creates a fiber in :ready status with a fresh monotonic id."
  (with-clean-fibers
    (let* ((f1
          (cl-cc/runtime::rt-make-fiber
            (lambda ()
              1)))
           (f2
          (cl-cc/runtime::rt-make-fiber
            (lambda ()
              2))))
      (expect (cl-cc/runtime::rt-fiber-status f1) :to-be :ready)
      (expect
        (< (cl-cc/runtime::rt-fiber-id f1) (cl-cc/runtime::rt-fiber-id f2))
        :to-be-truthy))))

(it-sequential
  "rt-fiber-schedule enqueues the fiber and marks it :ready."
  (with-clean-fibers
    (let ((f
          (cl-cc/runtime::rt-make-fiber
            (lambda ()
              :x))))
      (cl-cc/runtime::rt-fiber-schedule f)
      (expect (member f cl-cc/runtime::*rt-fiber-ready*) :to-be-truthy)
      (expect (cl-cc/runtime::rt-fiber-status f) :to-be :ready))))

(it-sequential
  "rt-fiber-spawn builds and schedules a fiber in one step."
  (with-clean-fibers
    (let ((f
          (cl-cc/runtime::rt-fiber-spawn
            (lambda ()
              :spawned))))
      (expect (member f cl-cc/runtime::*rt-fiber-ready*) :to-be-truthy))))

;;; ─── Resume: completion, result, failure ────────────────────────────────────
(it-sequential
  "Resuming a ready fiber runs its thunk, captures the result, marks it :done."
  (with-clean-fibers
    (let ((f
          (cl-cc/runtime::rt-make-fiber
            (lambda ()
              (+ 20 22)))))
      (expect (cl-cc/runtime::rt-fiber-resume f) :to-equal 42)
      (expect (cl-cc/runtime::rt-fiber-done-p f) :to-be-truthy)
      (expect (cl-cc/runtime::rt-fiber-result f) :to-equal 42))))

(it-sequential
  "A thunk that signals an error leaves the fiber :failed with the condition
recorded and rt-fiber-resume returning NIL."
  (with-clean-fibers
    (let ((f
          (cl-cc/runtime::rt-make-fiber
            (lambda ()
              (error "boom")))))
      (expect (cl-cc/runtime::rt-fiber-resume f) :to-be-null)
      (expect (cl-cc/runtime::rt-fiber-status-failed-p f) :to-be-truthy)
      (expect (typep (cl-cc/runtime::rt-fiber-error f) (quote error)) :to-be-truthy))))

(it-sequential
  "Resuming an already-finished fiber is a no-op that returns the cached result."
  (with-clean-fibers
    (let ((f
          (cl-cc/runtime::rt-make-fiber
            (lambda ()
              :done-once))))
      (cl-cc/runtime::rt-fiber-resume f)
      (expect (cl-cc/runtime::rt-fiber-resume f) :to-be :done-once))))

(it-sequential
  "When a fiber has an attached future, completing it resolves that future."
  (with-clean-fibers
    (let* ((fut (cl-cc/runtime::rt-make-future))
           (f
          (cl-cc/runtime::rt-make-fiber
            (lambda ()
              :fiber-value)
            :future
            fut)))
      (cl-cc/runtime::rt-fiber-resume f)
      (expect (cl-cc/runtime::rt-future-done-p fut) :to-be-truthy)
      (expect (cl-cc/runtime::rt-future-await fut) :to-be :fiber-value))))

(it-sequential
  "A failing fiber resolves its future with the signalled condition."
  (with-clean-fibers
    (let* ((fut (cl-cc/runtime::rt-make-future))
           (f
          (cl-cc/runtime::rt-make-fiber
            (lambda ()
              (error "kaboom"))
            :future
            fut)))
      (cl-cc/runtime::rt-fiber-resume f)
      (expect
        (typep (cl-cc/runtime::rt-future-await fut) (quote error))
        :to-be-truthy))))

;;; ─── Continuations: set-continuation, block, resume ─────────────────────────
(it-sequential
  "rt-fiber-set-continuation installs the next step and marks the fiber
:suspended; a later resume runs that continuation."
  (with-clean-fibers
    (let ((f
          (cl-cc/runtime::rt-make-fiber
            (lambda ()
              :never-run-thunk))))
      (cl-cc/runtime::rt-fiber-set-continuation
        f
        (lambda ()
          :resumed-step))
      (expect (cl-cc/runtime::rt-fiber-status f) :to-be :suspended)
      (expect (cl-cc/runtime::rt-fiber-resume f) :to-be :resumed-step)
      (expect (cl-cc/runtime::rt-fiber-done-p f) :to-be-truthy))))

(it-sequential
  "rt-fiber-set-continuation requires a fiber and a function."
  (with-clean-fibers
    (let ((f
          (cl-cc/runtime::rt-make-fiber
            (lambda ()
              :x))))
      (signals type-error (cl-cc/runtime::rt-fiber-set-continuation f :not-a-fn)))))

(it-sequential "Calling rt-fiber-yield from inside a running fiber records the yielded value
and re-schedules the fiber as :ready." (with-clean-fibers
    (let ((f (cl-cc/runtime::rt-make-fiber
              (lambda () (cl-cc/runtime::rt-fiber-yield :paused)))))
      (cl-cc/runtime::rt-fiber-resume f)
      ;; yield set status back to :ready and pushed the fiber onto the queue.
      (expect (cl-cc/runtime::rt-fiber-status f) :to-be :ready)
      (expect (cl-cc/runtime::rt-fiber-yielded-value f) :to-be :paused)
      (expect (member f cl-cc/runtime::*rt-fiber-ready*) :to-be-truthy))))

(it-sequential
  "Outside any fiber, rt-fiber-yield simply returns its argument."
  (with-clean-fibers (expect (cl-cc/runtime::rt-fiber-yield :val) :to-be :val)))

;;; ─── Fiber-locals ───────────────────────────────────────────────────────────
(it-sequential
  "rt-fiber-local reads and writes per-fiber storage while the fiber runs."
  (with-clean-fibers
    (let ((f
          (cl-cc/runtime::rt-make-fiber
            (lambda ()
              (setf (cl-cc/runtime::rt-fiber-local :k) :stored)
              (cl-cc/runtime::rt-fiber-local :k)))))
      (expect (cl-cc/runtime::rt-fiber-resume f) :to-be :stored))))

(it-sequential
  "Outside a fiber rt-fiber-local returns the default and setf errors."
  (with-clean-fibers
    (expect (cl-cc/runtime::rt-fiber-local :missing :dflt) :to-be :dflt)
    (signals error (setf (cl-cc/runtime::rt-fiber-local :k) 1))))

;;; ─── Running the ready queue ────────────────────────────────────────────────
(it-sequential
  "rt-run-fibers resumes every ready fiber until the queue empties."
  (with-clean-fibers
    (let ((log nil))
      (dolist (i '(1 2 3))
        (cl-cc/runtime::rt-fiber-spawn
          (let ((i i))
            (lambda ()
              (push i log)))))
      (cl-cc/runtime::rt-run-fibers)
      (expect cl-cc/runtime::*rt-fiber-ready* :to-be-null)
      (expect (sort log #'<) :to-equal '(1 2 3)))))

(it-sequential "rt-run-fibers with :once resumes exactly one fiber and returns it." (with-clean-fibers
    (let ((ran nil))
      (cl-cc/runtime::rt-fiber-spawn (lambda () (push :a ran)))
      (cl-cc/runtime::rt-fiber-spawn (lambda () (push :b ran)))
      (let ((f (cl-cc/runtime::rt-run-fibers :once t)))
        (expect (cl-cc/runtime::rt-fiber-p f) :to-be-truthy)
        (expect (length ran) :to-equal 1)
        ;; One fiber remains queued.
        (expect (length cl-cc/runtime::*rt-fiber-ready*) :to-equal 1)))))

;;; ─── rt-fiber-async: fiber + future ─────────────────────────────────────────
(it-sequential
  "rt-fiber-async spawns a fiber and returns a future resolved once the fiber
is run."
  (with-clean-fibers
    (let ((fut
          (cl-cc/runtime::rt-fiber-async
            (lambda ()
              :async-result))))
      (expect (cl-cc/runtime::rt-future-done-p fut) :to-be-falsy)
      (cl-cc/runtime::rt-run-fibers)
      (expect (cl-cc/runtime::rt-future-done-p fut) :to-be-truthy)
      (expect (cl-cc/runtime::rt-future-await fut) :to-be :async-result))))

(it-sequential
  "rt-fiber-await on an already-resolved future returns its value directly."
  (with-clean-fibers
    (let ((fut (cl-cc/runtime::rt-make-future)))
      (cl-cc/runtime::rt-future-resolve fut :ready)
      (expect (cl-cc/runtime::rt-fiber-await fut) :to-be :ready))))

;;; ─── Green-thread dispatch fallback ─────────────────────────────────────────
(it-sequential
  "With neither a work-stealing nor a global scheduler bound, rt-green-thread-spawn
falls back to spawning a fiber."
  (with-clean-fibers
    (let ((cl-cc/runtime::*rt-work-stealing-scheduler* nil)
          (cl-cc/runtime::*rt-global-scheduler* nil))
      (let ((f
            (cl-cc/runtime::rt-green-thread-spawn
              (lambda ()
                :gt)
              :scheduler
              nil)))
        (expect (cl-cc/runtime::rt-fiber-p f) :to-be-truthy)
        (expect (member f cl-cc/runtime::*rt-fiber-ready*) :to-be-truthy)))))

(it-sequential
  "rt-run-green-threads drains the fiber queue when no scheduler is bound."
  (with-clean-fibers
    (let ((cl-cc/runtime::*rt-work-stealing-scheduler* nil)
          (cl-cc/runtime::*rt-global-scheduler* nil)
          (ran nil))
      (cl-cc/runtime::rt-fiber-spawn
        (lambda ()
          (setf ran t)))
      (cl-cc/runtime::rt-run-green-threads)
      (expect ran :to-be-truthy))))

;;; ─── Property: a fiber returning n resumes to exactly n ──────────────────────
(cl-weave:it-property
  "fiber result equals its thunk's return value"
  ((n (cl-weave:gen-integer :min -500 :max 500)))
  (let ((cl-cc/runtime::*rt-fiber-ready* nil)
        (cl-cc/runtime::*rt-current-fiber* nil))
    (let ((f
          (cl-cc/runtime::rt-make-fiber
            (lambda ()
              n))))
      (cl-cc/runtime::rt-fiber-resume f)
      (and
        (cl-cc/runtime::rt-fiber-done-p f)
        (eql n (cl-cc/runtime::rt-fiber-result f))))))
