;;;; scheduler-thread-pool.lisp — Fixed-size native thread pool built on
;;;; scheduler-native-thread.lisp, split out of scheduler.lisp
(in-package :cl-cc/runtime)

(defstruct rt-thread-pool
  (scheduler (rt-make-scheduler))
  (size 0)
  (threads nil)
  (shutdown-p nil))

(defun rt-make-thread-pool (&key (size 1))
  (make-rt-thread-pool :size size))

(defun rt-thread-pool-submit (pool thunk &key (priority :normal))
  (let* ((s (rt-thread-pool-scheduler pool))
         (th (%make-rt-green-thread :id (incf (rt-scheduler-counter s))
                                    :thunk thunk :priority priority)))
    (rt-with-mutex ((rt-scheduler-mutex s))
      (%rt-scheduler-enqueue s th))
    th))

(defun rt-thread-pool-run (pool)
  (let ((*rt-global-scheduler* (rt-thread-pool-scheduler pool)))
    (rt-scheduler-run)))

(defun rt-thread-pool-start (pool)
  (dotimes (i (rt-thread-pool-size pool) pool)
    (push (sb-thread:make-thread
           (lambda ()
             (loop until (rt-thread-pool-shutdown-p pool)
                   do (rt-thread-pool-run pool)
                      (sleep 0.001)))
           :name (format nil "rt-pool-~D" i))
          (rt-thread-pool-threads pool))))

(defun rt-thread-pool-shutdown (pool)
  (setf (rt-thread-pool-shutdown-p pool) t)
  pool)
