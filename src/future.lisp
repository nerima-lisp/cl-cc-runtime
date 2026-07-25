;;;; Future/Promise (FR-283)
(in-package :cl-cc/runtime)
(defstruct rt-future
  (value nil) (values nil) (resolved-p nil)
  (mutex (rt-make-mutex)) (cond (rt-make-condition-variable)))
(defun rt-make-future () (make-rt-future))
(defun rt-future-resolve (f &rest values)
  (rt-with-mutex ((rt-future-mutex f))
    (setf (rt-future-value f) (first values)
          (rt-future-values f) values
          (rt-future-resolved-p f) t)
    (rt-condition-notify-all (rt-future-cond f)))
  (values-list values))
(defun rt-future-await (f &key timeout)
  "Block until F is resolved, or until TIMEOUT seconds have elapsed in
total, and return its values (or no values, on timeout).

Tracks a single deadline across retries rather than resetting TIMEOUT on
every wakeup, and explicitly re-locks F's mutex after a timed-out
RT-CONDITION-WAIT: SB-THREAD:CONDITION-WAIT only reacquires the mutex when
woken by a notification, not when it returns due to timeout."
  (let ((deadline (and timeout (+ (get-internal-real-time)
                                   (round (* timeout internal-time-units-per-second))))))
    (rt-mutex-lock (rt-future-mutex f))
    (unwind-protect
         (loop until (rt-future-resolved-p f)
               do (let ((remaining (and deadline
                                         (/ (max 0 (- deadline (get-internal-real-time)))
                                            (float internal-time-units-per-second)))))
                    (when (and deadline (<= remaining 0))
                      (return))
                    (unless (rt-condition-wait (rt-future-cond f) (rt-future-mutex f) :timeout remaining)
                      (rt-mutex-lock (rt-future-mutex f))
                      (return))))
      (rt-mutex-unlock (rt-future-mutex f))))
  (values-list (rt-future-values f)))
(defun rt-future-then (f callback)
  (let ((new-f (rt-make-future)))
    (rt-spawn (lambda ()
                 (multiple-value-call #'rt-future-resolve
                   new-f
                   (multiple-value-call callback (rt-future-await f)))))
    new-f))
(defun rt-future-done-p (f) (rt-future-resolved-p f))
(defun rt-all-futures (futures)
  (dolist (f futures) (rt-future-await f))
  futures)
