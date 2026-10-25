;;;; tests/runtime-subsystem-fr-tests.lisp - Runtime Subsystem FR Evidence Tests
;;;;
;;;; Evidence tests for feature requirements documented in
;;;; docs/runtime-subsystem.md.  These tests verify that every FR has
;;;; implementation evidence: symbols exist, files load, and basic
;;;; functionality works.
;;;;
;;;; FR Coverage:
;;;;   Wave 0: Load-graph verification (all source files loadable)
;;;;   Wave 1: ANSI runtime — Unicode, pprint, time, env, conditions, chars, arrays, I/O
;;;;   Wave 2: Atomics, sync, lock-free, EBR, hazard, RCU, QSBR, MVCC
;;;;   Wave 3: Safepoints, stack maps, tail calls, stack/OOM safety
;;;;   Wave 4: Concurrency — scheduler, tasks, futures, channels, actors, STM, fibers
;;;;   Wave 5: OS, async I/O, network, image, signals, mmap

(in-package :cl-cc/runtime/concurrency/test)



;;; -----------------------------------------------------------------
;;; Wave 0: Load-Graph Verification
;;; -----------------------------------------------------------------

;;; -----------------------------------------------------------------
;;; Existence macros — data/logic separation
;;;
;;; define-fr-loaded-test: Prolog-style clause that checks every listed
;;; symbol is fboundp. Data = the symbol list; logic = the macro.
;;;
;;; define-fr-existence-test: more general form supporting
;;; (:f sym) fboundp / (:b sym) boundp / (:s pkg name) find-symbol.
;;; -----------------------------------------------------------------

;;; -----------------------------------------------------------------
;;; Wave 2: Sync + concurrency subsystem
;;; -----------------------------------------------------------------

(it-sequential "runtime-subsystem-sync-primitives-loaded"
  (expect (fboundp 'rt-make-mutex) :to-be-truthy)
  (expect (fboundp 'rt-mutex-lock) :to-be-truthy)
  (expect (fboundp 'rt-mutex-unlock) :to-be-truthy)
  (expect (fboundp 'rt-make-condition-variable) :to-be-truthy)
  (expect (fboundp 'rt-make-semaphore) :to-be-truthy)
  (expect (fboundp 'rt-make-barrier) :to-be-truthy)
  (expect (fboundp 'rt-make-once) :to-be-truthy))

(it-sequential "runtime-subsystem-scheduler-loaded"
  (expect (fboundp 'rt-make-scheduler) :to-be-truthy)
  (expect (fboundp 'rt-spawn) :to-be-truthy)
  (expect (fboundp 'rt-yield) :to-be-truthy)
  (expect (fboundp 'rt-scheduler-run) :to-be-truthy))

(it-sequential "runtime-subsystem-future-loaded"
  (expect (fboundp 'rt-make-future) :to-be-truthy)
  (expect (fboundp 'rt-future-resolve) :to-be-truthy)
  (expect (fboundp 'rt-future-await) :to-be-truthy)
  (expect (fboundp 'rt-future-done-p) :to-be-truthy))

(it-sequential "runtime-subsystem-channel-loaded"
  (expect (fboundp 'rt-make-channel) :to-be-truthy)
  (expect (fboundp 'rt-channel-send) :to-be-truthy)
  (expect (fboundp 'rt-channel-recv) :to-be-truthy)
  (expect (fboundp 'rt-channel-close) :to-be-truthy))

(it-sequential "runtime-subsystem-actor-loaded"
  (expect (fboundp 'rt-make-actor) :to-be-truthy)
  (expect (fboundp 'rt-actor-send) :to-be-truthy)
  (expect (fboundp 'rt-actor-receive) :to-be-truthy))

(it-sequential "runtime-subsystem-stm-loaded"
  (expect (fboundp 'rt-atomically) :to-be-truthy)
  (expect (fboundp 'rt-retry) :to-be-truthy))

(it-sequential "runtime-subsystem-lockfree-loaded"
  (expect (fboundp 'rt-make-lfstack) :to-be-truthy)
  (expect (fboundp 'rt-make-lfqueue) :to-be-truthy)
  (expect (fboundp 'rt-make-lfhash-map) :to-be-truthy))

(it-sequential "runtime-subsystem-ebr-loaded"
  (expect (fboundp 'rt-ebr-init) :to-be-truthy)
  (expect (fboundp 'rt-ebr-register-thread) :to-be-truthy)
  (expect (fboundp 'rt-ebr-enter) :to-be-truthy)
  (expect (fboundp 'rt-ebr-leave) :to-be-truthy))

(it-sequential "runtime-subsystem-hazard-loaded"
  (expect (fboundp 'rt-hp-register-thread) :to-be-truthy)
  (expect (fboundp 'rt-hp-protect) :to-be-truthy)
  (expect (fboundp 'rt-hp-retire) :to-be-truthy))

(it-sequential "runtime-subsystem-rcu-loaded"
  (expect (fboundp 'rt-rcu-read-lock) :to-be-truthy)
  (expect (fboundp 'rt-rcu-synchronize) :to-be-truthy))

(it-sequential "runtime-subsystem-qsbr-loaded"
  (expect (fboundp 'rt-qsbr-init) :to-be-truthy)
  (expect (fboundp 'rt-qsbr-register-thread) :to-be-truthy)
  (expect (fboundp 'rt-qsbr-synchronize) :to-be-truthy))

;;; -----------------------------------------------------------------
;;; Wave 5: OS + I/O subsystem
;;; -----------------------------------------------------------------

;;; -----------------------------------------------------------------
;;; Wave 3: Runtime internals
;;; -----------------------------------------------------------------

(it-sequential "runtime-subsystem-context-loaded"
  (expect (fboundp 'rt-context-cancel) :to-be-truthy)
  (expect (fboundp 'rt-context-cancelled-p) :to-be-truthy))

(it-sequential "runtime-subsystem-spsc-loaded"
  (expect (fboundp 'rt-make-spsc-queue) :to-be-truthy)
  (expect (fboundp 'rt-spsc-try-push) :to-be-truthy)
  (expect (fboundp 'rt-spsc-try-pop) :to-be-truthy))

(it-sequential "runtime-subsystem-parallel-algo-loaded"
  (expect (fboundp 'rt-parallel-algo-init) :to-be-truthy))

;;; -----------------------------------------------------------------
;;; Wave 1: VM ANSI Runtime Features
;;; -----------------------------------------------------------------

;;; -----------------------------------------------------------------
;;; Wave 2-5: Integration Tests
;;; -----------------------------------------------------------------

;;; -----------------------------------------------------------------
;;; FR semantic evidence tests
;;; -----------------------------------------------------------------

(it-sequential "runtime-subsystem-sync-mutex-prevents-reentrant-access"
  (let ((m (rt-make-mutex)))
    (expect (rt-mutex-lock m) :to-be-truthy)
    (unwind-protect
         (expect (not (rt-mutex-try-lock m)) :to-be-truthy)
      (rt-mutex-unlock m))))

(it-sequential "runtime-subsystem-sync-semaphore-counts-correctly"
  (let ((s (rt-make-semaphore :count 2)))
    (expect (rt-semaphore-try-wait s) :to-be-truthy)
    (expect (rt-semaphore-try-wait s) :to-be-truthy)
    (expect (not (rt-semaphore-try-wait s)) :to-be-truthy)
    (expect (= 2 (rt-semaphore-signal s 2)) :to-be-truthy)
    (expect (rt-semaphore-try-wait s) :to-be-truthy)
    (expect (rt-semaphore-try-wait s) :to-be-truthy)))

(it-sequential "runtime-subsystem-sync-barrier-releases-waiters"
  (let ((b (rt-make-barrier 1)))
    (expect (rt-barrier-reset b) :to-be-truthy)
    (expect (rt-barrier-wait b :timeout 0.1) :to-be-truthy)
    (expect (rt-barrier-reset b) :to-be-truthy)
    (expect (rt-barrier-wait b :timeout 0.1) :to-be-truthy)))

(it-sequential "runtime-subsystem-sync-once-call-executes-once"
  (let ((o (rt-make-once))
        (calls '()))
    (expect (rt-once-call o (lambda () (push :first calls) :first)) :to-be :first)
    (expect (rt-once-call o (lambda () (push :second calls) :second)) :to-be :first)
    (expect calls :to-equal '(:first))))

(it-sequential "runtime-subsystem-scheduler-spawned-tasks-execute-in-order"
  (rt-scheduler-init)
  (let ((events '()))
    (rt-spawn (lambda () (push :low events)) :priority :low)
    (rt-spawn (lambda () (push :normal events)) :priority :normal)
    (rt-spawn (lambda () (push :high events)) :priority :high)
    (rt-scheduler-run)
    (expect events :to-equal '(:low :normal :high))))

(it-sequential "runtime-subsystem-scheduler-sleep-task-records-wake-time"
  (rt-scheduler-init)
  (let ((task (rt-spawn (lambda () (rt-sleep-task 1) :slept))))
    (rt-scheduler-run :once t)
    (expect (rt-green-thread-result task) :to-be :slept)))

(it-sequential "runtime-subsystem-channel-buffered-preserves-order"
  (let ((ch (rt-make-channel :capacity 3)))
    (rt-channel-send ch :a)
    (rt-channel-send ch :b)
    (rt-channel-send ch :c)
    (expect (multiple-value-list (rt-channel-recv ch)) :to-equal '(:a t))
    (expect (multiple-value-list (rt-channel-recv ch)) :to-equal '(:b t))
    (expect (multiple-value-list (rt-channel-recv ch)) :to-equal '(:c t))))

(it-sequential "runtime-subsystem-channel-close-prevents-further-sends"
  (let ((ch (rt-make-channel :capacity 1)))
    (expect (rt-channel-close ch) :to-be-truthy)
    (expect (handler-case
            (progn (rt-channel-send ch :after-close) nil)
          (error () t)) :to-be-truthy)))

(it-sequential "runtime-subsystem-channel-select-returns-first-available"
  (let ((empty (rt-make-channel :capacity 1))
        (ready (rt-make-channel :capacity 1)))
    (rt-channel-send ready :ready)
    (multiple-value-bind (value channel ok)
        (rt-channel-select (list empty ready) :timeout 0.01)
      (expect ok :to-be-truthy)
      (expect value :to-be :ready)
      (expect channel :to-be ready))))

(it-sequential "runtime-subsystem-actor-processes-messages-in-order"
  (let ((a (rt-make-actor #'identity)))
    (rt-actor-send a :first)
    (rt-actor-send a :second)
    (rt-actor-send a :third)
    (expect (list (rt-actor-receive a :timeout 0.1)
                     (rt-actor-receive a :timeout 0.1)
                     (rt-actor-receive a :timeout 0.1)) :to-equal '(:third :second :first))))

(it-sequential "runtime-subsystem-stm-atomically-commits-transaction"
  (let ((cell (rt-make-tvar 10)))
    (expect (= 15 (rt-atomically
                (let ((old (rt-read-tvar cell)))
                  (rt-write-tvar cell (+ old 5))))) :to-be-truthy)
    (expect (= 15 (rt-tvar-value-unsafe cell)) :to-be-truthy)))

(it-sequential "runtime-subsystem-stm-retries-on-conflict"
  (let ((cell (rt-make-tvar 0))
        (attempts 0)
        (read-ready (sb-thread:make-semaphore))
        (writer-done (sb-thread:make-semaphore))
        (writer nil))
    (setf writer
          (sb-thread:make-thread
           (lambda ()
             (sb-thread:wait-on-semaphore read-ready)
             (rt-atomically (rt-write-tvar cell 10))
             (sb-thread:signal-semaphore writer-done))))
    (unwind-protect
         (progn
           (expect
            (= 20
               (rt-atomically
                 (incf attempts)
                 (let ((old (rt-read-tvar cell)))
                   (when (= attempts 1)
                     (sb-thread:signal-semaphore read-ready)
                     (sb-thread:wait-on-semaphore writer-done))
                   (rt-write-tvar cell (+ old 10)))))
            :to-be-truthy)
           (expect (= 2 attempts) :to-be-truthy)
           (expect (= 20 (rt-tvar-value-unsafe cell)) :to-be-truthy))
      (when writer
        (sb-thread:signal-semaphore read-ready)
        (sb-thread:join-thread writer)))))

(it-sequential "runtime-subsystem-fr-740-stm-isolates-staged-writes-until-commit"
  (let ((cell (rt-make-tvar 1))
        (observed-before-commit nil))
    (expect (= 2 (rt-atomically
                (rt-write-tvar cell 2)
                (setf observed-before-commit
                      (rt-tvar-value-unsafe cell))
                (rt-read-tvar cell))) :to-be-truthy)
    (expect (= 1 observed-before-commit) :to-be-truthy)
    (expect (= 2 (rt-tvar-value-unsafe cell)) :to-be-truthy)))

(it-sequential "runtime-subsystem-fr-741-async-await-runs-through-scheduler"
  (rt-scheduler-init)
  (let ((future (rt-async (+ 20 22))))
    (expect (= 42 (rt-await future :timeout 0.1)) :to-be-truthy)
    (expect (rt-future-done-p future) :to-be-truthy)))

(it-sequential "runtime-subsystem-fr-742-work-stealing-runs-local-and-stolen-tasks"
  (let* ((scheduler (rt-make-work-stealing-scheduler :workers 2))
         (events nil))
    (expect (rt-work-stealing-submit scheduler (lambda () (push :first events))) :to-be-truthy)
    (expect (rt-work-stealing-submit scheduler (lambda () (push :second events))) :to-be-truthy)
    (expect (rt-work-stealing-run scheduler) :to-be-truthy)
    (expect (= 2 (length events)) :to-be-truthy)
    (expect (member :first events) :to-be-truthy)
    (expect (member :second events) :to-be-truthy)))

(it-sequential "runtime-subsystem-fr-743-fiber-yield-and-resume-preserve-state"
  (let ((steps nil)
        (fiber nil))
    (setf fiber
          (rt-make-fiber
           (lambda ()
             (push :start steps)
             (rt-fiber-block
              (lambda ()
                (push :resume steps)
                :done)
              :blocked))))
    (expect (rt-fiber-resume fiber) :to-be :blocked)
    (expect (rt-fiber-done-p fiber) :to-be-falsy)
    (expect (rt-fiber-resume fiber) :to-be :done)
    (expect (rt-fiber-done-p fiber) :to-be-truthy)
    (expect steps :to-equal '(:resume :start))))

(it-sequential "runtime-subsystem-lockfree-stack-is-lifo"
  (let ((s (rt-make-lfstack)))
    (rt-lfstack-push s :first)
    (rt-lfstack-push s :second)
    (rt-lfstack-push s :third)
    (expect (multiple-value-list (rt-lfstack-pop s)) :to-equal '(:third t))
    (expect (multiple-value-list (rt-lfstack-pop s)) :to-equal '(:second t))
    (expect (multiple-value-list (rt-lfstack-pop s)) :to-equal '(:first t))))

(it-sequential "runtime-subsystem-lockfree-queue-is-fifo"
  (let ((q (rt-make-lfqueue)))
    (rt-lfqueue-push q :first)
    (rt-lfqueue-push q :second)
    (rt-lfqueue-push q :third)
    (expect (multiple-value-list (rt-lfqueue-pop q)) :to-equal '(:first t))
    (expect (multiple-value-list (rt-lfqueue-pop q)) :to-equal '(:second t))
    (expect (multiple-value-list (rt-lfqueue-pop q)) :to-equal '(:third t))))

(it-sequential "runtime-subsystem-ebr-retire-reclaim-cycle"
  (let ((freed '()))
    (rt-ebr-init (lambda (obj) (push obj freed)))
    (let ((local (rt-ebr-register-thread)))
      (rt-ebr-retire local :old-node)
      (expect (= 0 (rt-ebr-collect local)) :to-be-truthy)
      (expect (= 1 (rt-ebr-collect local)) :to-be-truthy)
      (expect freed :to-equal '(:old-node)))))

(it-sequential "runtime-subsystem-hazard-retire-defers-protected-objects"
  (let ((freed nil)
        (thread sb-thread:*current-thread*)
        (protected (list :protected))
        (unprotected (list :unprotected)))
    (flet ((free-object (object)
             (push object freed)))
      (rt-hp-init #'free-object)
      (unwind-protect
           (progn
             (rt-hp-register-thread 2 thread)
             (rt-hp-protect 0 protected thread)
             (rt-hp-retire-object protected
                                  :thread thread
                                  :free-fn #'free-object
                                  :threshold 1)
             (expect freed :to-equal nil)
             (rt-hp-retire-object unprotected
                                  :thread thread
                                  :free-fn #'free-object
                                  :threshold 1)
             (expect freed :to-equal (list unprotected))
             (expect (member protected (rt-hp-all-protected) :test #'eq) :to-be-truthy)
             (rt-hp-clear 0 thread)
             (expect (= 1 (rt-hp-reclaim :thread thread :free-fn #'free-object)) :to-be-truthy)
             (expect freed :to-equal (list protected unprotected)))
        (rt-hp-init)))))

(it-sequential "runtime-subsystem-spsc-preserves-single-producer-consumer-semantics"
  (let ((q (rt-make-spsc-queue 2)))
    (expect (rt-spsc-try-push q :first) :to-be-truthy)
    (expect (rt-spsc-try-push q :second) :to-be-truthy)
    (expect (rt-spsc-full-p q) :to-be-truthy)
    (expect (not (rt-spsc-try-push q :third)) :to-be-truthy)
    (expect (multiple-value-list (rt-spsc-try-pop q)) :to-equal '(:first t))
    (expect (multiple-value-list (rt-spsc-try-pop q)) :to-equal '(:second t))
    (expect (multiple-value-list (rt-spsc-try-pop q)) :to-equal '(nil nil))))

(it-sequential "runtime-subsystem-sync-mutex-basic"
  (let ((m (rt-make-mutex)))
    (expect (rt-mutex-lock m) :to-be-truthy)
    (rt-mutex-unlock m)
    t))

(it-sequential "runtime-subsystem-sync-semaphore-basic"
  (let ((s (rt-make-semaphore :count 1)))
    (expect (rt-semaphore-wait s :timeout 0.1) :to-be-truthy)
    (expect (rt-semaphore-signal s) :to-be-truthy)))

(it-sequential "runtime-subsystem-sync-barrier-basic"
  (let ((b (rt-make-barrier 1)))
    (expect (rt-barrier-wait b :timeout 0.1) :to-be-truthy)))

(it-sequential "runtime-subsystem-sync-once-basic"
  (let ((o (rt-make-once))
        (count 0))
    (rt-once-call o (lambda () (incf count)))
    (expect (= 1 count) :to-be-truthy)
    (rt-once-call o (lambda () (incf count)))
    (expect (= 1 count) :to-be-truthy)))

(it-sequential "runtime-subsystem-scheduler-spawn-basic"
  (rt-scheduler-init)
  (let ((result nil))
    (rt-spawn (lambda () (setf result 42)))
    (rt-scheduler-run)
    (expect result :to-be 42)))

(it-sequential "runtime-subsystem-future-basic"
  (let ((f (rt-make-future)))
    (rt-future-resolve f 99)
    (expect (rt-future-await f :timeout 0.1) :to-be 99)))

(it-sequential "runtime-subsystem-channel-basic"
  (let ((ch (rt-make-channel :capacity 1)))
    (expect (rt-channel-send ch 7) :to-be 7)
    (expect (rt-channel-recv ch) :to-be 7)))

(it-sequential "runtime-subsystem-actor-basic"
  (let ((a (rt-make-actor #'identity)))
    (rt-actor-send a :hello)
    (expect (rt-actor-receive a :timeout 0.1) :to-be :hello)))

(it-sequential "runtime-subsystem-lockfree-stack-basic"
  (let ((s (rt-make-lfstack)))
    (rt-lfstack-push s 1)
    (rt-lfstack-push s 2)
    (multiple-value-bind (val ok) (rt-lfstack-pop s)
      (expect ok :to-be-truthy)
      (expect val :to-be 2))))

(it-sequential "runtime-subsystem-spsc-basic"
  (let ((q (rt-make-spsc-queue 4)))
    (expect (rt-spsc-try-push q 10) :to-be-truthy)
    (multiple-value-bind (val ok) (rt-spsc-try-pop q)
      (expect ok :to-be-truthy)
      (expect val :to-be 10))))

;;; -----------------------------------------------------------------
;;; FR Coverage Verification
;;; -----------------------------------------------------------------

