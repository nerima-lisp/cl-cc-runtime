(in-package :cl-cc/runtime/resilience)

(defstruct rt-token-bucket
  (limiter nil)
  (dropped 0 :type integer)
  (accepted 0 :type integer)
  (stats-lock (sb-thread:make-mutex :name "cl-cc rate limiter stats")))

(defun rt-make-token-bucket (&key (rate 10.0) (burst 10.0))
  (make-rt-token-bucket
   :limiter (make-rate-limiter :refill-rate rate :capacity burst)))
(defun %rt-token-bucket-record-result (bucket acquired-p)
  (sb-thread:with-mutex ((rt-token-bucket-stats-lock bucket))
    (if acquired-p
        (incf (rt-token-bucket-accepted bucket))
        (incf (rt-token-bucket-dropped bucket))))
  acquired-p)

(defun rt-token-bucket-try-acquire (bucket &optional (n 1))
  (multiple-value-bind (acquired-p retry-after)
      (rate-limiter-acquire (rt-token-bucket-limiter bucket) :tokens n)
    (declare (ignore retry-after))
    (%rt-token-bucket-record-result bucket acquired-p)))

(defun rt-token-bucket-acquire (bucket &optional (n 1))
  (rt-token-bucket-try-acquire bucket n))

(defun rt-token-bucket-wait (bucket &optional (n 1) &key timeout)
  (multiple-value-bind (acquired-p retry-after)
      (rate-limiter-acquire (rt-token-bucket-limiter bucket)
                            :tokens n
                            :wait-p t
                            :max-wait timeout)
    (declare (ignore retry-after))
    (%rt-token-bucket-record-result bucket acquired-p)))

(defun rt-token-bucket-rate (bucket)
  (rate-limiter-refill-rate (rt-token-bucket-limiter bucket)))

(defun rt-token-bucket-burst (bucket)
  (rate-limiter-capacity (rt-token-bucket-limiter bucket)))

(defun rt-token-bucket-last (bucket)
  (rate-limiter-last-refill (rt-token-bucket-limiter bucket)))

(defun rt-token-bucket-tokens (bucket)
  (rate-limiter-tokens (rt-token-bucket-limiter bucket)))

(defun rt-token-bucket-stats (bucket)
  (let ((tokens (rate-limiter-tokens (rt-token-bucket-limiter bucket))))
    (sb-thread:with-mutex ((rt-token-bucket-stats-lock bucket))
      (list :tokens tokens
            :accepted (rt-token-bucket-accepted bucket)
            :dropped (rt-token-bucket-dropped bucket)))))
