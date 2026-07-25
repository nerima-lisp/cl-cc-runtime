;;;; runtime-stack.lisp — Call-depth guard, return-address poisoning, OOM/GC-pressure conditions
(in-package :cl-cc/runtime)

(defparameter *max-call-stack-depth* 10000
  "Maximum native/runtime logical call stack depth before stack overflow.")

(defvar *rt-call-stack-depth* 0
  "Current logical runtime call depth for stack guard instrumentation.")

(define-condition rt-stack-overflow (storage-condition)
  ((depth :initarg :depth :reader rt-stack-overflow-depth)
   (limit :initarg :limit :reader rt-stack-overflow-limit))
  (:report (lambda (c s)
             (format s "Runtime stack overflow at depth ~D (limit ~D)"
                     (rt-stack-overflow-depth c)
                     (rt-stack-overflow-limit c)))))

(define-condition rt-oom-condition (storage-condition)
  ((requested-words :initarg :requested-words :reader rt-oom-requested-words)
   (limit-words :initarg :limit-words :reader rt-oom-limit-words)
   (used-words :initarg :used-words :reader rt-oom-used-words))
  (:report (lambda (c s)
             (format s "Runtime heap exhausted: requested ~D words, used ~D, limit ~D"
                     (rt-oom-requested-words c)
                     (rt-oom-used-words c)
                     (rt-oom-limit-words c)))))

(define-condition rt-gc-pressure-warning (warning)
  ((heap :initarg :heap :reader rt-gc-pressure-warning-heap)
   (occupancy :initarg :occupancy :reader rt-gc-pressure-warning-occupancy)
   (threshold :initarg :threshold :reader rt-gc-pressure-warning-threshold))
  (:report (lambda (c s)
             (format s "Runtime heap pressure ~,1F% crossed ~D% threshold"
                     (rt-gc-pressure-warning-occupancy c)
                     (rt-gc-pressure-warning-threshold c)))))

(defconstant +rt-return-address-poison-mask+ #x5afe000000000000
  "High-bit poison mask used to tag VM/runtime return addresses.")

(defun rt-poison-return-address (return-address)
  "Tag RETURN-ADDRESS so accidental use as an object/code pointer is detectable."
  (check-type return-address integer)
  (logxor return-address +rt-return-address-poison-mask+))

(defun rt-unpoison-return-address (poisoned-address)
  "Recover the original return address from POISONED-ADDRESS."
  (check-type poisoned-address integer)
  (logxor poisoned-address +rt-return-address-poison-mask+))

(defun rt-return-address-poisoned-p (value)
  "Return true when VALUE carries the runtime return-address poison tag."
  (and (integerp value)
       (= (logand value +rt-return-address-poison-mask+)
          +rt-return-address-poison-mask+)))

(defun rt-check-stack-overflow (&optional (depth *rt-call-stack-depth*))
  "Signal RT-STACK-OVERFLOW when DEPTH reaches *MAX-CALL-STACK-DEPTH*."
  (when (>= depth *max-call-stack-depth*)
    (error 'rt-stack-overflow :depth depth :limit *max-call-stack-depth*))
  depth)

(defmacro rt-with-call-stack-guard (() &body body)
  "Run BODY with runtime call-depth accounting and stack overflow guard."
  `(let ((*rt-call-stack-depth* (1+ *rt-call-stack-depth*)))
     (rt-check-stack-overflow)
     ,@body))

(defun rt-signal-oom (requested-words &key heap (limit-words nil) (used-words nil))
  "Signal a STORAGE-CONDITION for runtime out-of-memory paths."
  (error 'rt-oom-condition
         :requested-words requested-words
         :limit-words (or limit-words (and heap (rt-heap-max-heap-words heap)) 0)
         :used-words (or used-words (and heap (ignore-errors (%rt-heap-live-used-words heap))) 0)))

(defun rt-check-heap-pressure-thresholds (heap)
  "Warn at fixed 80/90/95% heap pressure thresholds and return occupancy." 
  (let ((occupancy (rt-heap-occupancy-pct heap)))
    (dolist (threshold '(80 90 95))
      (when (>= occupancy threshold)
        (warn 'rt-gc-pressure-warning
              :heap heap :occupancy occupancy :threshold threshold)))
    occupancy))
