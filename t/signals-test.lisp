(in-package :cl-cc-runtime/test)

;;;; Tests for src/signals.lisp — POSIX signal bookkeeping (FR-348/FR-572).
;;;;
;;;; SAFETY: these never raise a real OS signal. Handler dispatch is exercised by
;;;; calling rt-dispatch-os-signal / rt-process-pending-signals directly, and the
;;;; handler tables are dynamically re-bound to fresh hash tables so nothing
;;;; leaks into the running image. The few tests that touch the native disposition
;;;; (rt-set-signal-handler / rt-install-signal-handler) use benign SIGUSR1/USR2
;;;; and reset to :default in an unwind-protect. Unexported symbols are
;;;; cl-cc/runtime:: qualified.
;;; ── Pure mappings ─────────────────────────────────────────────────
(it-sequential
  "Known signal numbers map to their keyword names."
  (expect (cl-cc/runtime::rt-signal-name +rt-sigint+) :to-be :sigint)
  (expect (cl-cc/runtime::rt-signal-name +rt-sigterm+) :to-be :sigterm)
  (expect (cl-cc/runtime::rt-signal-name +rt-sigusr1+) :to-be :sigusr1))

(it-sequential
  "An unmapped signal number reports :unknown."
  (expect (cl-cc/runtime::rt-signal-name 9999) :to-be :unknown))

(it-sequential
  "Signal numbers map to their specialized CL condition classes."
  (expect
    (cl-cc/runtime::rt-signal-condition-class +rt-sigint+)
    :to-be
    'cl-cc/runtime::rt-interrupt)
  (expect
    (cl-cc/runtime::rt-signal-condition-class 8)
    :to-be
    'cl-cc/runtime::rt-floating-point-exception)
  (expect
    (cl-cc/runtime::rt-signal-condition-class +rt-sigusr1+)
    :to-be
    'cl-cc/runtime::rt-os-signal-condition))

(it-sequential
  "rt-signal-to-condition builds a condition tagged with signal + name."
  (let ((c (cl-cc/runtime::rt-signal-to-condition +rt-sigint+)))
    (expect (typep c 'cl-cc/runtime::rt-interrupt) :to-be-truthy)
    (expect (cl-cc/runtime::rt-os-signal c) :to-equal +rt-sigint+)
    (expect (cl-cc/runtime::rt-os-signal-name c) :to-be :sigint)))

;;; ── Mask bookkeeping ──────────────────────────────────────────────
(it-sequential "rt-signal-mask records blocked signals and returns the prior mask." (let ((cl-cc/runtime::*rt-signal-mask* nil))
    (expect (rt-signal-mask +rt-sigusr1+) :to-be-null)
    (expect (member +rt-sigusr1+ cl-cc/runtime::*rt-signal-mask*) :to-be-truthy)
    ;; second call returns the previous (non-empty) mask
    (expect (member +rt-sigusr1+ (rt-signal-mask +rt-sigusr2+)) :to-be-truthy)
    (expect (member +rt-sigusr2+ cl-cc/runtime::*rt-signal-mask*) :to-be-truthy)))

(it-sequential
  "rt-unblock-signal drops a signal from the mask mirror."
  (let ((cl-cc/runtime::*rt-signal-mask* (list +rt-sigusr1+ +rt-sigusr2+)))
    (expect (rt-unblock-signal +rt-sigusr1+) :to-equal +rt-sigusr1+)
    (expect (member +rt-sigusr1+ cl-cc/runtime::*rt-signal-mask*) :to-be-falsy)
    (expect (member +rt-sigusr2+ cl-cc/runtime::*rt-signal-mask*) :to-be-truthy)))

;;; ── Dispatch (no real OS signal) ──────────────────────────────────
(it-sequential
  "rt-dispatch-os-signal runs registered handlers then signals the condition."
  (let ((cl-cc/runtime::*rt-signal-handlers* (make-hash-table))
        (called nil)
        (condition-seen nil))
    (setf (gethash +rt-sigusr1+ cl-cc/runtime::*rt-signal-handlers*) (list
        (cl-cc/runtime::make-rt-signal-handler
          :signal
          +rt-sigusr1+
          :function
          (lambda (sig)
            (setf called sig)))))
    (handler-bind ((cl-cc/runtime::rt-os-signal-condition
          (lambda (c)
            (setf condition-seen c))))
      (cl-cc/runtime::rt-dispatch-os-signal +rt-sigusr1+))
    (expect called :to-equal +rt-sigusr1+)
    (expect condition-seen :to-be-truthy)))

(it-sequential
  "A one-shot handler is removed after firing once."
  (let ((cl-cc/runtime::*rt-signal-handlers* (make-hash-table))
        (count 0))
    (setf (gethash +rt-sigusr2+ cl-cc/runtime::*rt-signal-handlers*) (list
        (cl-cc/runtime::make-rt-signal-handler
          :signal
          +rt-sigusr2+
          :function
          (lambda (sig)
            (declare (ignore sig))
            (incf count))
          :one-shot-p
          t)))
    (cl-cc/runtime::rt-dispatch-os-signal +rt-sigusr2+)
    (cl-cc/runtime::rt-dispatch-os-signal +rt-sigusr2+)
    (expect count :to-equal 1)
    (expect (gethash +rt-sigusr2+ cl-cc/runtime::*rt-signal-handlers*) :to-be-null)))

(it-sequential
  "Deferred (pending) signals are dispatched on process-pending-signals."
  (let ((cl-cc/runtime::*rt-signal-handlers* (make-hash-table))
        (cl-cc/runtime::*pending-signals* nil)
        (cl-cc/runtime::*rt-signal-mask* nil)
        (fired nil))
    (setf (gethash +rt-sigusr1+ cl-cc/runtime::*rt-signal-handlers*) (list
        (cl-cc/runtime::make-rt-signal-handler
          :signal
          +rt-sigusr1+
          :function
          (lambda (sig)
            (push sig fired)))))
    (cl-cc/runtime::%rt-record-pending-signal +rt-sigusr1+)
    (let ((processed (rt-process-pending-signals)))
      (expect processed :to-equal (list +rt-sigusr1+))
      (expect fired :to-equal (list +rt-sigusr1+)))))

(it-sequential
  "A masked pending signal is not dispatched."
  (let ((cl-cc/runtime::*rt-signal-handlers* (make-hash-table))
        (cl-cc/runtime::*pending-signals* nil)
        (cl-cc/runtime::*rt-signal-mask* (list +rt-sigusr1+))
        (fired nil))
    (setf (gethash +rt-sigusr1+ cl-cc/runtime::*rt-signal-handlers*) (list
        (cl-cc/runtime::make-rt-signal-handler
          :signal
          +rt-sigusr1+
          :function
          (lambda (sig)
            (push sig fired)))))
    (cl-cc/runtime::%rt-record-pending-signal +rt-sigusr1+)
    (rt-process-pending-signals)
    (expect fired :to-be-null)))

(it-sequential
  "Shutdown hooks are each called with the signal number."
  (let* ((cl-cc/runtime::*shutdown-hooks* nil)
         (seen nil))
    (push
      (lambda (sig)
        (push sig seen))
      cl-cc/runtime::*shutdown-hooks*)
    (expect (cl-cc/runtime::%rt-run-shutdown-hooks +rt-sigterm+) :to-be-truthy)
    (expect seen :to-equal (list +rt-sigterm+))))

;;; ── remove-signal-handler ─────────────────────────────────────────
(it-sequential
  "rt-remove-signal-handler unlinks a specific handler from its signal list."
  (let* ((cl-cc/runtime::*rt-signal-handlers* (make-hash-table))
         (h
        (cl-cc/runtime::make-rt-signal-handler
          :signal
          +rt-sigusr1+
          :function
          (lambda (s)
            (declare (ignore s))))))
    (setf (gethash +rt-sigusr1+ cl-cc/runtime::*rt-signal-handlers*) (list h))
    (expect (cl-cc/runtime::rt-remove-signal-handler h) :to-be-truthy)
    (expect (gethash +rt-sigusr1+ cl-cc/runtime::*rt-signal-handlers*) :to-be-null)))

;;; ── Native disposition (benign signals, restored) ─────────────────
(it-sequential
  "rt-set-signal-handler stores :default / :ignore and get reflects them."
  (let ((cl-cc/runtime::*rt-signal-handlers* (make-hash-table))
        (cl-cc/runtime::*rt-sigaction-installed* (make-hash-table)))
    (unwind-protect (progn
        (expect (rt-set-signal-handler +rt-sigusr1+ :ignore) :to-be :ignore)
        (expect (rt-get-signal-handler +rt-sigusr1+) :to-be :ignore)
        (expect (rt-set-signal-handler +rt-sigusr1+ :default) :to-be :default)
        (expect (rt-get-signal-handler +rt-sigusr1+) :to-be :default))
      (sb-sys:enable-interrupt +rt-sigusr1+ :default))))

(it-sequential
  "A user function installed via rt-set-signal-handler is returned by get."
  (let ((cl-cc/runtime::*rt-signal-handlers* (make-hash-table))
        (cl-cc/runtime::*rt-sigaction-installed* (make-hash-table))
        (fn
        (lambda (sig)
          (declare (ignore sig))
          :ok)))
    (unwind-protect (progn
        (rt-set-signal-handler +rt-sigusr2+ fn)
        (expect (rt-get-signal-handler +rt-sigusr2+) :to-be fn))
      (sb-sys:enable-interrupt +rt-sigusr2+ :default))))

(it-sequential
  "A signal with no handler installed reports :default."
  (let ((cl-cc/runtime::*rt-signal-handlers* (make-hash-table))
        (cl-cc/runtime::*rt-sigaction-installed* (make-hash-table)))
    (expect (rt-get-signal-handler +rt-sigwinch+) :to-be :default)))

(it-sequential
  "rt-install-signal-handler returns a handler struct registered for the signal."
  (let ((cl-cc/runtime::*rt-signal-handlers* (make-hash-table))
        (cl-cc/runtime::*rt-sigaction-installed* (make-hash-table)))
    (unwind-protect (let ((h
            (cl-cc/runtime::rt-install-signal-handler
              +rt-sigusr1+
              (lambda (s)
                (declare (ignore s))))))
        (expect (cl-cc/runtime::rt-signal-handler-signal h) :to-equal +rt-sigusr1+)
        (expect
          (member h (gethash +rt-sigusr1+ cl-cc/runtime::*rt-signal-handlers*))
          :to-be-truthy))
      (sb-sys:enable-interrupt +rt-sigusr1+ :default))))

(it-sequential "rt-with-signal-handler installs a handler for BODY and restores afterward." (let ((cl-cc/runtime::*rt-signal-handlers* (make-hash-table))
        (cl-cc/runtime::*rt-sigaction-installed* (make-hash-table)))
    (unwind-protect
         (progn
           (rt-with-signal-handler (+rt-sigusr2+ :ignore)
             (expect (rt-get-signal-handler +rt-sigusr2+) :to-be :ignore))
           ;; restored to the prior disposition (:default) after the body
           (expect (rt-get-signal-handler +rt-sigusr2+) :to-be :default))
      (sb-sys:enable-interrupt +rt-sigusr2+ :default))))

(it-sequential
  "rt-clear-signal-handlers empties the registry (optionally per-signal)."
  (let ((cl-cc/runtime::*rt-signal-handlers* (make-hash-table)))
    (setf (gethash +rt-sigusr1+ cl-cc/runtime::*rt-signal-handlers*) (list :x)
          (gethash +rt-sigusr2+ cl-cc/runtime::*rt-signal-handlers*) (list :y))
    (rt-clear-signal-handlers +rt-sigusr1+)
    (expect (gethash +rt-sigusr1+ cl-cc/runtime::*rt-signal-handlers*) :to-be-null)
    (expect
      (gethash +rt-sigusr2+ cl-cc/runtime::*rt-signal-handlers*)
      :to-be-truthy)
    (rt-clear-signal-handlers)
    (expect (gethash +rt-sigusr2+ cl-cc/runtime::*rt-signal-handlers*) :to-be-null)))
