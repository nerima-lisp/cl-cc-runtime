;;;; t/sync-test.lisp — synchronization primitives (src/sync.lisp).
;;;;
;;;; Uses real sb-thread threads with join-based correctness gates (no timing
;;;; assertions). A broken primitive shows up either as a wrong final value or as
;;;; a hang caught by the suite timeout, never as a flaky pass.
(in-package :cl-cc-runtime/test)

(describe
  "mutex (sync.lisp)"
  (it
    "serializes concurrent increments with no lost updates"
    (let* ((m (cl-cc/runtime::rt-make-mutex))
           (counter 0)
           (n 8)
           (per 1000)
           (threads
          (loop repeat n
                collect (sb-thread:make-thread
              (lambda ()
                (dotimes (i per)
                  (cl-cc/runtime::rt-with-mutex
                    (m)
                    (setf counter (1+ counter)))))))))
      (dolist (th threads)
        (sb-thread:join-thread th))
      (expect counter :to-be (* n per))))
  (it
    "try-lock succeeds on a free mutex"
    (let ((m (cl-cc/runtime::rt-make-mutex)))
      (expect (cl-cc/runtime::rt-mutex-try-lock m) :to-be-truthy)
      (cl-cc/runtime::rt-mutex-unlock m)))
  (it
    "try-lock fails when another thread holds the mutex"
    (let ((m (cl-cc/runtime::rt-make-mutex))
          (result :unset))
      (cl-cc/runtime::rt-mutex-lock m)
      (let ((th
            (sb-thread:make-thread
              (lambda ()
                (setf result (cl-cc/runtime::rt-mutex-try-lock m))))))
        (sb-thread:join-thread th))
      (cl-cc/runtime::rt-mutex-unlock m)
      (expect result :to-be-null)))
  (it
    "records the current thread as owner while held"
    (let ((m (cl-cc/runtime::rt-make-mutex)))
      (cl-cc/runtime::rt-mutex-lock m)
      (expect (cl-cc/runtime::rt-mutex-owner m) :to-be sb-thread:*current-thread*)
      (cl-cc/runtime::rt-mutex-unlock m)
      (expect (cl-cc/runtime::rt-mutex-owner m) :to-be-null)))
  (it
    "with a TIMEOUT and the mutex already held elsewhere, does not run BODY and returns NIL"
    ;; RT-WITH-MUTEX used to run BODY (and unconditionally unlock) regardless
    ;; of whether the timed acquisition actually succeeded, so a timed-out
    ;; caller executed its critical section with no mutual exclusion at all.
    ;; BODY-RAN staying NIL is the direct evidence that regression stays fixed.
    (let* ((m (cl-cc/runtime::rt-make-mutex))
           (body-ran nil)
           (holder-ready nil)
           (release-holder nil))
      (let ((holder
            (sb-thread:make-thread
              (lambda ()
                (cl-cc/runtime::rt-with-mutex
                  (m)
                  (setf holder-ready t)
                  (loop until release-holder do (sleep 0.005)))))))
        (loop until holder-ready do (sleep 0.005))
        (expect
          (cl-cc/runtime::rt-with-mutex (m :timeout 0.05) (setf body-ran t) :ran)
          :to-be-null)
        (expect body-ran :to-be-null)
        (setf release-holder t)
        (sb-thread:join-thread holder)))))

(describe
  "recursive mutex (sync.lisp)"
  (it
    "the owner may re-enter, tracked by a depth counter"
    (let ((rm (cl-cc/runtime::rt-make-recursive-mutex)))
      (expect (cl-cc/runtime::rt-recursive-mutex-lock rm) :to-be-truthy)
      (expect (cl-cc/runtime::rt-recursive-mutex-lock rm) :to-be-truthy)
      (expect (cl-cc/runtime::rt-recursive-mutex-depth rm) :to-be 2)
      (cl-cc/runtime::rt-recursive-mutex-unlock rm)
      (expect (cl-cc/runtime::rt-recursive-mutex-depth rm) :to-be 1)
      (cl-cc/runtime::rt-recursive-mutex-unlock rm)
      (expect (cl-cc/runtime::rt-recursive-mutex-owner rm) :to-be-null)))
  (it
    "unlock by a non-owner signals an error"
    (let ((rm (cl-cc/runtime::rt-make-recursive-mutex)))
      (signals error (cl-cc/runtime::rt-recursive-mutex-unlock rm))))
  (it
    "excludes other threads while held"
    (let ((rm (cl-cc/runtime::rt-make-recursive-mutex))
          (got :unset))
      (cl-cc/runtime::rt-recursive-mutex-lock rm)
      (let ((th
            (sb-thread:make-thread
              (lambda ()
                (setf got (cl-cc/runtime::rt-recursive-mutex-try-lock rm))))))
        (sb-thread:join-thread th))
      (cl-cc/runtime::rt-recursive-mutex-unlock rm)
      (expect got :to-be-null))))

(describe "semaphore (sync.lisp)"
  (it "signal then wait succeeds and decrements the count"
    (let ((s (cl-cc/runtime::rt-make-semaphore :count 0)))
      (cl-cc/runtime::rt-semaphore-signal s 2)
      (expect (cl-cc/runtime::rt-semaphore-wait s) :to-be-truthy)
      (expect (cl-cc/runtime::rt-semaphore-wait s) :to-be-truthy)
      (expect (cl-cc/runtime::rt-semaphore-count s) :to-be 0)))

  (it "try-wait fails at zero and succeeds after a signal"
    (let ((s (cl-cc/runtime::rt-make-semaphore :count 0)))
      (expect (cl-cc/runtime::rt-semaphore-try-wait s) :to-be-null)
      (cl-cc/runtime::rt-semaphore-signal s)
      (expect (cl-cc/runtime::rt-semaphore-try-wait s) :to-be-truthy)))

  (it "a blocked waiter is released by a signal from another thread"
    (let ((s (cl-cc/runtime::rt-make-semaphore :count 0)) (done nil))
      (let ((waiter (sb-thread:make-thread
                     (lambda ()
                       (cl-cc/runtime::rt-semaphore-wait s)
                       (setf done t)))))
        (sleep 0.05)                    ; let the waiter reach the blocking wait
        (cl-cc/runtime::rt-semaphore-signal s)
        (sb-thread:join-thread waiter))
      (expect done :to-be-truthy)))

  (it "counts producers and consumers exactly across threads"
    (let* ((s (cl-cc/runtime::rt-make-semaphore :count 0))
           (consumed 0) (n 4) (per 200)
           (lock (cl-cc/runtime::rt-make-mutex))
           (consumers (loop repeat n collect
                            (sb-thread:make-thread
                             (lambda ()
                               (dotimes (i per)
                                 (cl-cc/runtime::rt-semaphore-wait s)
                                 (cl-cc/runtime::rt-with-mutex (lock) (incf consumed))))))))
      (dotimes (i (* n per)) (cl-cc/runtime::rt-semaphore-signal s))
      (dolist (th consumers) (sb-thread:join-thread th))
      (expect consumed :to-be (* n per))))

  (it "with TIMEOUT and no permit ever signalled, gives up promptly instead of blocking forever"
    ;; RT-SEMAPHORE-WAIT used to pass no timeout at all to its inner
    ;; RT-CONDITION-WAIT -- TIMEOUT bounded only the initial lock
    ;; acquisition, never the actual wait for a permit.
    (let ((s (cl-cc/runtime::rt-make-semaphore :count 0))
          (started (get-internal-real-time)))
      (expect (cl-cc/runtime::rt-semaphore-wait s :timeout 0.05) :to-be-null)
      (expect
        (< (- (get-internal-real-time) started) internal-time-units-per-second)
        :to-be-truthy))))

(describe
  "barrier (sync.lisp)"
  (it
    "releases all N threads once every party has arrived"
    (let* ((n 4)
           (b (cl-cc/runtime::rt-make-barrier n))
           (passed 0)
           (lock (cl-cc/runtime::rt-make-mutex))
           (threads
          (loop repeat n
                collect (sb-thread:make-thread
              (lambda ()
                (cl-cc/runtime::rt-barrier-wait b)
                (cl-cc/runtime::rt-with-mutex (lock) (incf passed)))))))
      (dolist (th threads)
        (sb-thread:join-thread th))
      (expect passed :to-be n)))
  (it
    "is reusable across multiple generations"
    (let* ((n 3)
           (b (cl-cc/runtime::rt-make-barrier n))
           (rounds 2)
           (passed 0)
           (lock (cl-cc/runtime::rt-make-mutex))
           (threads
          (loop repeat n
                collect (sb-thread:make-thread
              (lambda ()
                (dotimes (r rounds)
                  (cl-cc/runtime::rt-barrier-wait b)
                  (cl-cc/runtime::rt-with-mutex (lock) (incf passed))))))))
      (dolist (th threads)
        (sb-thread:join-thread th))
      (expect passed :to-be (* n rounds))))
  (it
    "with TIMEOUT and never enough parties, gives up promptly instead of blocking forever"
    ;; RT-BARRIER-WAIT used to re-pass the original TIMEOUT to every
    ;; RT-CONDITION-WAIT in its loop instead of a shrinking remaining
    ;; duration, so a generation that had not yet advanced re-armed the
    ;; full budget on every spurious wakeup rather than counting against it.
    (let ((b (cl-cc/runtime::rt-make-barrier 2))
          (started (get-internal-real-time)))
      (expect (cl-cc/runtime::rt-barrier-wait b :timeout 0.05) :to-be-null)
      (expect
        (< (- (get-internal-real-time) started) internal-time-units-per-second)
        :to-be-truthy))))

(describe
  "condition variable (sync.lisp)"
  (it
    "wait-until wakes when another thread sets the predicate and notifies"
    (let* ((m (cl-cc/runtime::rt-make-mutex))
           (cv (cl-cc/runtime::rt-make-condition-variable))
           (ready nil)
           (result nil))
      (let ((waiter
            (sb-thread:make-thread
              (lambda ()
                (cl-cc/runtime::rt-with-mutex
                  (m)
                  (cl-cc/runtime::rt-condition-wait-until
                    cv
                    m
                    (lambda ()
                      ready)
                    :timeout
                    1.0))
                (setf result t)))))
        (sleep 0.05)
        (cl-cc/runtime::rt-with-mutex
          (m)
          (setf ready t)
          (cl-cc/runtime::rt-condition-notify cv))
        (sb-thread:join-thread waiter))
      (expect result :to-be-truthy)))
  (it
    "notify-all releases every waiter"
    (let* ((m (cl-cc/runtime::rt-make-mutex))
           (cv (cl-cc/runtime::rt-make-condition-variable))
           (ready nil)
           (woken 0)
           (lock (cl-cc/runtime::rt-make-mutex))
           (waiters
          (loop repeat 4
                collect (sb-thread:make-thread
              (lambda ()
                (cl-cc/runtime::rt-with-mutex
                  (m)
                  (cl-cc/runtime::rt-condition-wait-until
                    cv
                    m
                    (lambda ()
                      ready)
                    :timeout
                    1.0))
                (cl-cc/runtime::rt-with-mutex (lock) (incf woken)))))))
      (sleep 0.05)
      (cl-cc/runtime::rt-with-mutex
        (m)
        (setf ready t)
        (cl-cc/runtime::rt-condition-notify-all cv))
      (dolist (th waiters)
        (sb-thread:join-thread th))
      (expect woken :to-be 4))))

(describe
  "read-write lock (sync.lisp)"
  (it
    "allows multiple concurrent readers"
    (let ((rw (cl-cc/runtime::rt-make-rwlock))
          (got :unset))
      (expect (cl-cc/runtime::rt-rwlock-try-read-lock rw) :to-be-truthy)
      (let ((th
            (sb-thread:make-thread
              (lambda ()
                (setf got (cl-cc/runtime::rt-rwlock-try-read-lock rw))))))
        (sb-thread:join-thread th))
      (expect got :to-be-truthy)
      (expect (cl-cc/runtime::rt-rwlock-readers rw) :to-be 2)
      (cl-cc/runtime::rt-rwlock-read-unlock rw)
      (cl-cc/runtime::rt-rwlock-read-unlock rw)))
  (it
    "a held write lock blocks a would-be reader's try"
    (let ((rw (cl-cc/runtime::rt-make-rwlock))
          (got :unset))
      (cl-cc/runtime::rt-rwlock-write-lock rw)
      (let ((th
            (sb-thread:make-thread
              (lambda ()
                (setf got (cl-cc/runtime::rt-rwlock-try-read-lock rw))))))
        (sb-thread:join-thread th))
      (cl-cc/runtime::rt-rwlock-write-unlock rw)
      (expect got :to-be-null)))
  (it
    "a held read lock blocks a would-be writer's try"
    (let ((rw (cl-cc/runtime::rt-make-rwlock))
          (got :unset))
      (cl-cc/runtime::rt-rwlock-read-lock rw)
      (let ((th
            (sb-thread:make-thread
              (lambda ()
                (setf got (cl-cc/runtime::rt-rwlock-try-write-lock rw))))))
        (sb-thread:join-thread th))
      (cl-cc/runtime::rt-rwlock-read-unlock rw)
      (expect got :to-be-null)))
  (it
    "write locks serialize concurrent writers with no lost updates"
    (let* ((rw (cl-cc/runtime::rt-make-rwlock))
           (counter 0)
           (n 6)
           (per 500)
           (threads
          (loop repeat n
                collect (sb-thread:make-thread
              (lambda ()
                (dotimes (i per)
                  (cl-cc/runtime::rt-with-write-lock
                    (rw)
                    (setf counter (1+ counter)))))))))
      (dolist (th threads)
        (sb-thread:join-thread th))
      (expect counter :to-be (* n per))))
  (it
    "read-unlock without a reader signals an error"
    (let ((rw (cl-cc/runtime::rt-make-rwlock)))
      (signals error (cl-cc/runtime::rt-rwlock-read-unlock rw))))
  (it
    "write-unlock without a writer signals an error"
    (let ((rw (cl-cc/runtime::rt-make-rwlock)))
      (signals error (cl-cc/runtime::rt-rwlock-write-unlock rw))))
  (it
    "read-lock with TIMEOUT gives up promptly, not after blocking forever, while a writer holds the lock"
    ;; RT-RWLOCK-READ-LOCK/WRITE-LOCK used to re-pass the original TIMEOUT to
    ;; every RT-CONDITION-WAIT in their loops instead of a shrinking
    ;; remaining duration -- see RT-BARRIER-WAIT's regression test above.
    (let ((rw (cl-cc/runtime::rt-make-rwlock))
          (started (get-internal-real-time)))
      (cl-cc/runtime::rt-rwlock-write-lock rw)
      (expect (cl-cc/runtime::rt-rwlock-read-lock rw :timeout 0.05) :to-be-null)
      (expect
        (< (- (get-internal-real-time) started) internal-time-units-per-second)
        :to-be-truthy)
      (cl-cc/runtime::rt-rwlock-write-unlock rw)))
  (it
    "write-lock with TIMEOUT gives up promptly, not after blocking forever, while a reader holds the lock"
    (let ((rw (cl-cc/runtime::rt-make-rwlock))
          (started (get-internal-real-time)))
      (cl-cc/runtime::rt-rwlock-read-lock rw)
      (expect (cl-cc/runtime::rt-rwlock-write-lock rw :timeout 0.05) :to-be-null)
      (expect
        (< (- (get-internal-real-time) started) internal-time-units-per-second)
        :to-be-truthy)
      (cl-cc/runtime::rt-rwlock-read-unlock rw))))

(describe
  "once (sync.lisp)"
  (it
    "runs the thunk exactly once under concurrency and caches its result"
    (let* ((o (cl-cc/runtime::rt-make-once))
           (calls 0)
           (n 8)
           (lock (cl-cc/runtime::rt-make-mutex))
           (threads
          (loop repeat n
                collect (sb-thread:make-thread
              (lambda ()
                (cl-cc/runtime::rt-once-call
                  o
                  (lambda ()
                    (cl-cc/runtime::rt-with-mutex (lock) (incf calls))
                    :the-result)))))))
      (dolist (th threads)
        (sb-thread:join-thread th))
      (expect calls :to-be 1)
      (expect
        (cl-cc/runtime::rt-once-call
          o
          (lambda ()
            :ignored))
        :to-be
        :the-result))))

(describe
  "sync init (sync.lisp)"
  (it
    "rt-sync-init returns t"
    (expect (cl-cc/runtime::rt-sync-init) :to-be-truthy)))
