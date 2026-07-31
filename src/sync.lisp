;;;; Synchronization Primitives (FR-370-373)
(in-package :cl-cc/runtime)
(defstruct rt-mutex (name nil) (host-mutex (sb-thread:make-mutex)) (owner nil) (recursive-p nil))
(defun rt-make-mutex (&key name recursive-p) (make-rt-mutex :name name :recursive-p recursive-p))
(defun rt-mutex-lock (m &key timeout)
  (let ((thread (%rt-current-thread)))
    (rt-deadlock-before-lock m thread)
    (let ((ok (if timeout
                  (sb-thread:grab-mutex (rt-mutex-host-mutex m) :timeout timeout)
                  (progn (sb-thread:grab-mutex (rt-mutex-host-mutex m)) t))))
      (rt-deadlock-after-lock m thread ok)
      (when ok
        (rt-tsan-acquire m)
        (setf (rt-mutex-owner m) thread)
        t))))
(defun rt-mutex-unlock (m)
  (let ((thread (%rt-current-thread)))
    (rt-tsan-release m)
    (sb-thread:release-mutex (rt-mutex-host-mutex m))
    (when (eq (rt-mutex-owner m) thread)
      (setf (rt-mutex-owner m) nil))
    (rt-deadlock-after-unlock m thread)
    t))
(defmacro rt-with-mutex ((m &key timeout) &body body)
  "Run BODY with M held, returning its value, or NIL without running BODY at
all when TIMEOUT is given and the lock is not acquired in time. The previous
form ran BODY (and unconditionally called RT-MUTEX-UNLOCK) regardless of
whether RT-MUTEX-LOCK actually returned true, so a timed-out caller executed
its critical section with no mutual exclusion in effect and then released a
mutex it had never acquired."
  (let ((mutex (gensym "MUTEX")) (acquired (gensym "ACQUIRED")))
    `(let* ((,mutex ,m)
            (,acquired (rt-mutex-lock ,mutex :timeout ,timeout)))
       (when ,acquired
         (unwind-protect (progn ,@body)
           (rt-mutex-unlock ,mutex))))))

(defmacro rt-with-remaining-timeout ((remaining-fn timeout) &body body)
  "Bind (REMAINING-FN) inside BODY to a function of no arguments returning the
seconds left before TIMEOUT elapses, recomputed fresh on every call, or NIL
(unbounded) when TIMEOUT is NIL. For a retry loop whose wait primitive needs
a shrinking duration on each iteration: passing the same TIMEOUT to every
RT-CONDITION-WAIT call in a loop re-arms the full budget on every spurious
wakeup or unmet condition, so the effective wait becomes an unbounded
multiple of TIMEOUT rather than TIMEOUT itself. Mirrors the deadline
RT-FUTURE-AWAIT already tracks, extracted here for the several other
RT-*-WAIT primitives with the same shape."
  (let ((deadline (gensym "DEADLINE")))
    `(let ((,deadline (and ,timeout (+ (get-internal-real-time)
                                       (round (* ,timeout internal-time-units-per-second))))))
       (flet ((,remaining-fn ()
                (and ,deadline
                     (max 0.0 (/ (- ,deadline (get-internal-real-time))
                                (float internal-time-units-per-second))))))
         ,@body))))

(defstruct rt-condition-variable (name nil) (waitqueue (sb-thread:make-waitqueue)))
(defun rt-make-condition-variable (&key name) (make-rt-condition-variable :name name))
(defparameter +rt-condition-wait-default-timeout-seconds+ 1e6
  "Default RT-CONDITION-WAIT timeout when the caller passes none: about 11.5
days, chosen to stand in for \"no timeout\" while still being a finite,
catchable value rather than an actual indefinite block. RT-MUTEX-LOCK and
RT-THREAD-JOIN block genuinely indefinitely when their own :TIMEOUT is
omitted; this function differs only because it always has to pass some
timeout value through to SB-THREAD:CONDITION-WAIT.")
(defun rt-condition-wait (cv m &key timeout)
  (rt-tsan-release m)
  (prog1 (sb-thread:condition-wait (rt-condition-variable-waitqueue cv)
                                   (rt-mutex-host-mutex m)
                                   :timeout (or timeout +rt-condition-wait-default-timeout-seconds+))
    (rt-tsan-acquire m)))
(defun rt-condition-notify (cv) (sb-thread:condition-notify (rt-condition-variable-waitqueue cv)))
(defun rt-condition-notify-all (cv)
  (sb-thread:condition-broadcast (rt-condition-variable-waitqueue cv)))
(defstruct rt-semaphore (name nil) (count 0) (m (rt-make-mutex)) (c (rt-make-condition-variable)))
(defun rt-make-semaphore (&key name count) (make-rt-semaphore :name name :count count))
(defun rt-semaphore-wait (s &key timeout)
  "Block until S has a permit and take it, returning T. With TIMEOUT and no
permit within that many seconds, returns NIL. The wait used to pass no
timeout at all to its inner RT-CONDITION-WAIT -- TIMEOUT bounded only the
initial lock acquisition, not the actual wait for a permit."
  (rt-with-remaining-timeout (remaining timeout)
    (rt-with-mutex ((rt-semaphore-m s) :timeout timeout)
      (loop while (<= (rt-semaphore-count s) 0)
            do (let ((r (remaining)))
                 (when (and timeout (<= r 0)) (return-from rt-semaphore-wait nil))
                 (unless (rt-condition-wait (rt-semaphore-c s) (rt-semaphore-m s) :timeout r)
                   (return-from rt-semaphore-wait nil))))
      (decf (rt-semaphore-count s))
      t)))
(defun rt-semaphore-signal (s &optional (n 1))
  (rt-with-mutex ((rt-semaphore-m s))
    (incf (rt-semaphore-count s) n)
    (dotimes (i n) (rt-condition-notify (rt-semaphore-c s)))
    (rt-semaphore-count s)))
(defstruct rt-barrier
  (name nil) (count 0) (total 0) (gen 0)
  (m (rt-make-mutex)) (c (rt-make-condition-variable)))
(defun rt-make-barrier (n &key name) (make-rt-barrier :name name :total n))
(defun rt-barrier-wait (b &key timeout)
  "Block until every participant has called this, returning T for whichever
call completes the barrier and NIL for the rest -- or, with TIMEOUT, NIL
once that many seconds pass without the barrier completing. The wait used
to re-pass the original TIMEOUT to every RT-CONDITION-WAIT in its loop
instead of a shrinking remaining duration, so a spurious wakeup or a
generation that had not yet advanced re-armed the full budget rather than
counting against it."
  (rt-with-remaining-timeout (remaining timeout)
    (rt-with-mutex ((rt-barrier-m b) :timeout timeout)
      (let ((g (rt-barrier-gen b)))
        (incf (rt-barrier-count b))
        (if (= (rt-barrier-count b) (rt-barrier-total b))
            (progn (setf (rt-barrier-count b) 0)
                   (incf (rt-barrier-gen b))
                   (rt-condition-notify-all (rt-barrier-c b))
                   t)
            (progn (loop while (= g (rt-barrier-gen b))
                         do (let ((r (remaining)))
                              (when (and timeout (<= r 0)) (return))
                              (unless (rt-condition-wait (rt-barrier-c b) (rt-barrier-m b) :timeout r)
                                (return))))
                   nil))))))
(defstruct rt-once (done-p nil) (m (rt-make-mutex)))
(defun rt-make-once () (make-rt-once))

(defun rt-once-call (o fn) (rt-with-mutex ((rt-once-m o)) (unless (rt-once-done-p o) (setf (rt-once-done-p o) (cons t (funcall fn))))) (cdr (rt-once-done-p o)))
(defun rt-mutex-try-lock (m)
  "Try to acquire M without blocking. Returns true on success, NIL if already locked."
  (handler-case
      (when (sb-thread:grab-mutex (rt-mutex-host-mutex m) :waitp nil)
        (rt-tsan-acquire m)
        (setf (rt-mutex-owner m) (%rt-current-thread))
        t)
    (error () nil)))
(defmacro rt-with-try-mutex ((m) &body body)
  `(when (rt-mutex-try-lock ,m)
     (unwind-protect (progn ,@body)
       (rt-mutex-unlock ,m))))

(defstruct rt-recursive-mutex
  (name nil)
  (mutex (rt-make-mutex))
  (owner nil)
  (depth 0))

(defun rt-make-recursive-mutex (&key name)
  (make-rt-recursive-mutex :name name))

(defun %rt-current-thread ()
  sb-thread:*current-thread*)

(defun rt-recursive-mutex-lock (m &key timeout)
  (let ((me (%rt-current-thread)))
    (if (eq (rt-recursive-mutex-owner m) me)
        (progn (incf (rt-recursive-mutex-depth m)) t)
        (when (rt-mutex-lock (rt-recursive-mutex-mutex m) :timeout timeout)
          (setf (rt-recursive-mutex-owner m) me
                (rt-recursive-mutex-depth m) 1)
          t))))

(defun rt-recursive-mutex-try-lock (m)
  (let ((me (%rt-current-thread)))
    (if (eq (rt-recursive-mutex-owner m) me)
        (progn (incf (rt-recursive-mutex-depth m)) t)
        (when (rt-mutex-try-lock (rt-recursive-mutex-mutex m))
          (setf (rt-recursive-mutex-owner m) me
                (rt-recursive-mutex-depth m) 1)
          t))))

(defun rt-recursive-mutex-unlock (m)
  (unless (eq (rt-recursive-mutex-owner m) (%rt-current-thread))
    (error "recursive mutex not owned by current thread: ~A" (rt-recursive-mutex-name m)))
  (decf (rt-recursive-mutex-depth m))
  (when (zerop (rt-recursive-mutex-depth m))
    (setf (rt-recursive-mutex-owner m) nil)
    (rt-mutex-unlock (rt-recursive-mutex-mutex m)))
  t)

(defmacro rt-with-recursive-mutex ((m &key timeout) &body body)
  "Run BODY with M held (reentrantly), returning its value, or NIL without
running BODY when TIMEOUT is given and the lock is not acquired in time. See
RT-WITH-MUTEX's docstring for why the acquisition result must gate BODY."
  (let ((mutex (gensym "MUTEX")) (acquired (gensym "ACQUIRED")))
    `(let* ((,mutex ,m)
            (,acquired (rt-recursive-mutex-lock ,mutex :timeout ,timeout)))
       (when ,acquired
         (unwind-protect (progn ,@body)
           (rt-recursive-mutex-unlock ,mutex))))))

(defstruct rt-rwlock
  (name nil)
  (mutex (rt-make-mutex))
  (readers-ok (rt-make-condition-variable))
  (writers-ok (rt-make-condition-variable))
  (readers 0)
  (writer nil)
  (waiting-writers 0))

(defun rt-make-rwlock (&key name)
  (make-rt-rwlock :name name))

(defun rt-rwlock-read-lock (rw &key timeout)
  "Block until no writer holds or is waiting for RW, then take a read lock and
return T -- or, with TIMEOUT, NIL once that many seconds pass without
acquiring one. See RT-BARRIER-WAIT's docstring for why the wait loop needs a
shrinking remaining duration rather than the original TIMEOUT re-armed on
every iteration."
  (rt-with-remaining-timeout (remaining timeout)
    (rt-with-mutex ((rt-rwlock-mutex rw) :timeout timeout)
      (loop while (or (rt-rwlock-writer rw) (> (rt-rwlock-waiting-writers rw) 0))
            do (let ((r (remaining)))
                 (when (and timeout (<= r 0)) (return-from rt-rwlock-read-lock nil))
                 (unless (rt-condition-wait (rt-rwlock-readers-ok rw) (rt-rwlock-mutex rw) :timeout r)
                   (return-from rt-rwlock-read-lock nil))))
      (incf (rt-rwlock-readers rw))
      t)))

(defun rt-rwlock-try-read-lock (rw)
  (rt-with-try-mutex ((rt-rwlock-mutex rw))
    (unless (or (rt-rwlock-writer rw) (> (rt-rwlock-waiting-writers rw) 0))
      (incf (rt-rwlock-readers rw))
      t)))

(defun rt-rwlock-read-unlock (rw)
  (rt-with-mutex ((rt-rwlock-mutex rw))
    (when (<= (rt-rwlock-readers rw) 0)
      (error "rwlock read-unlock without reader: ~A" (rt-rwlock-name rw)))
    (decf (rt-rwlock-readers rw))
    (when (and (zerop (rt-rwlock-readers rw)) (> (rt-rwlock-waiting-writers rw) 0))
      (rt-condition-notify (rt-rwlock-writers-ok rw)))
    t))

(defun rt-rwlock-write-lock (rw &key timeout)
  "Block until no reader or writer holds RW, then take the write lock and
return T -- or, with TIMEOUT, NIL once that many seconds pass without
acquiring one. See RT-BARRIER-WAIT's docstring for why the wait loop needs a
shrinking remaining duration rather than the original TIMEOUT re-armed on
every iteration."
  (rt-with-remaining-timeout (remaining timeout)
    (rt-with-mutex ((rt-rwlock-mutex rw) :timeout timeout)
      (incf (rt-rwlock-waiting-writers rw))
      (unwind-protect
           (progn
             (loop while (or (rt-rwlock-writer rw) (> (rt-rwlock-readers rw) 0))
                   do (let ((r (remaining)))
                        (when (and timeout (<= r 0)) (return-from rt-rwlock-write-lock nil))
                        (unless (rt-condition-wait (rt-rwlock-writers-ok rw) (rt-rwlock-mutex rw) :timeout r)
                          (return-from rt-rwlock-write-lock nil))))
             (setf (rt-rwlock-writer rw) (%rt-current-thread))
             t)
        (decf (rt-rwlock-waiting-writers rw))))))

(defun rt-rwlock-try-write-lock (rw)
  (rt-with-try-mutex ((rt-rwlock-mutex rw))
    (unless (or (rt-rwlock-writer rw) (> (rt-rwlock-readers rw) 0))
      (setf (rt-rwlock-writer rw) (%rt-current-thread))
      t)))

(defun rt-rwlock-write-unlock (rw)
  (rt-with-mutex ((rt-rwlock-mutex rw))
    (unless (rt-rwlock-writer rw)
      (error "rwlock write-unlock without writer: ~A" (rt-rwlock-name rw)))
    (setf (rt-rwlock-writer rw) nil)
    (if (> (rt-rwlock-waiting-writers rw) 0)
        (rt-condition-notify (rt-rwlock-writers-ok rw))
        (rt-condition-notify-all (rt-rwlock-readers-ok rw)))
    t))

(defmacro rt-with-read-lock ((rw &key timeout) &body body)
  "Run BODY with RW read-locked, returning its value, or NIL without running
BODY when TIMEOUT is given and the lock is not acquired in time. See
RT-WITH-MUTEX's docstring for why the acquisition result must gate BODY."
  (let ((lock (gensym "RWLOCK")) (acquired (gensym "ACQUIRED")))
    `(let* ((,lock ,rw)
            (,acquired (rt-rwlock-read-lock ,lock :timeout ,timeout)))
       (when ,acquired
         (unwind-protect (progn ,@body)
           (rt-rwlock-read-unlock ,lock))))))

(defmacro rt-with-write-lock ((rw &key timeout) &body body)
  "Run BODY with RW write-locked, returning its value, or NIL without running
BODY when TIMEOUT is given and the lock is not acquired in time. See
RT-WITH-MUTEX's docstring for why the acquisition result must gate BODY."
  (let ((lock (gensym "RWLOCK")) (acquired (gensym "ACQUIRED")))
    `(let* ((,lock ,rw)
            (,acquired (rt-rwlock-write-lock ,lock :timeout ,timeout)))
       (when ,acquired
         (unwind-protect (progn ,@body)
           (rt-rwlock-write-unlock ,lock))))))

(defun rt-condition-wait-until (cv m predicate &key timeout)
  "Wait while PREDICATE is false. Rechecks after wakeups to tolerate spurious wakeups."
  (loop until (funcall predicate)
        do (rt-condition-wait cv m :timeout timeout))
  t)

(defun rt-semaphore-try-wait (s)
  (rt-with-try-mutex ((rt-semaphore-m s))
    (when (> (rt-semaphore-count s) 0)
      (decf (rt-semaphore-count s))
      t)))

(defun rt-barrier-reset (b)
  (rt-with-mutex ((rt-barrier-m b))
    (setf (rt-barrier-count b) 0)
    (incf (rt-barrier-gen b))
    (rt-condition-notify-all (rt-barrier-c b))
    t))
(defun rt-sync-init () t)
