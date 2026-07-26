(in-package :cl-cc-runtime/test)
(in-suite cl-cc-unit-suite)

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

(deftest signals-name-lookup
  "Known signal numbers map to their keyword names."
  (assert-eq :sigint (cl-cc/runtime::rt-signal-name +rt-sigint+))
  (assert-eq :sigterm (cl-cc/runtime::rt-signal-name +rt-sigterm+))
  (assert-eq :sigusr1 (cl-cc/runtime::rt-signal-name +rt-sigusr1+)))

(deftest signals-name-unknown
  "An unmapped signal number reports :unknown."
  (assert-eq :unknown (cl-cc/runtime::rt-signal-name 9999)))

(deftest signals-condition-class-mapping
  "Signal numbers map to their specialized CL condition classes."
  (assert-eq 'cl-cc/runtime::rt-interrupt
             (cl-cc/runtime::rt-signal-condition-class +rt-sigint+))
  (assert-eq 'cl-cc/runtime::rt-floating-point-exception
             (cl-cc/runtime::rt-signal-condition-class 8))
  (assert-eq 'cl-cc/runtime::rt-os-signal-condition
             (cl-cc/runtime::rt-signal-condition-class +rt-sigusr1+)))

(deftest signals-to-condition-carries-signal-and-name
  "rt-signal-to-condition builds a condition tagged with signal + name."
  (let ((c (cl-cc/runtime::rt-signal-to-condition +rt-sigint+)))
    (assert-true (typep c 'cl-cc/runtime::rt-interrupt))
    (assert-= +rt-sigint+ (cl-cc/runtime::rt-os-signal c))
    (assert-eq :sigint (cl-cc/runtime::rt-os-signal-name c))))

;;; ── Mask bookkeeping ──────────────────────────────────────────────

(deftest signals-mask-blocks-and-returns-old
  "rt-signal-mask records blocked signals and returns the prior mask."
  (let ((cl-cc/runtime::*rt-signal-mask* nil))
    (assert-null (rt-signal-mask +rt-sigusr1+))
    (assert-true (member +rt-sigusr1+ cl-cc/runtime::*rt-signal-mask*))
    ;; second call returns the previous (non-empty) mask
    (assert-true (member +rt-sigusr1+ (rt-signal-mask +rt-sigusr2+)))
    (assert-true (member +rt-sigusr2+ cl-cc/runtime::*rt-signal-mask*))))

(deftest signals-unblock-removes-from-mask
  "rt-unblock-signal drops a signal from the mask mirror."
  (let ((cl-cc/runtime::*rt-signal-mask* (list +rt-sigusr1+ +rt-sigusr2+)))
    (assert-= +rt-sigusr1+ (rt-unblock-signal +rt-sigusr1+))
    (assert-false (member +rt-sigusr1+ cl-cc/runtime::*rt-signal-mask*))
    (assert-true (member +rt-sigusr2+ cl-cc/runtime::*rt-signal-mask*))))

;;; ── Dispatch (no real OS signal) ──────────────────────────────────

(deftest signals-dispatch-invokes-handler-and-signals-condition
  "rt-dispatch-os-signal runs registered handlers then signals the condition."
  (let ((cl-cc/runtime::*rt-signal-handlers* (make-hash-table))
        (called nil)
        (condition-seen nil))
    (setf (gethash +rt-sigusr1+ cl-cc/runtime::*rt-signal-handlers*)
          (list (cl-cc/runtime::make-rt-signal-handler
                 :signal +rt-sigusr1+
                 :function (lambda (sig) (setf called sig)))))
    (handler-bind ((cl-cc/runtime::rt-os-signal-condition
                     (lambda (c) (setf condition-seen c))))
      (cl-cc/runtime::rt-dispatch-os-signal +rt-sigusr1+))
    (assert-= +rt-sigusr1+ called)
    (assert-true condition-seen)))

(deftest signals-dispatch-removes-one-shot-handler
  "A one-shot handler is removed after firing once."
  (let ((cl-cc/runtime::*rt-signal-handlers* (make-hash-table))
        (count 0))
    (setf (gethash +rt-sigusr2+ cl-cc/runtime::*rt-signal-handlers*)
          (list (cl-cc/runtime::make-rt-signal-handler
                 :signal +rt-sigusr2+
                 :function (lambda (sig) (declare (ignore sig)) (incf count))
                 :one-shot-p t)))
    (cl-cc/runtime::rt-dispatch-os-signal +rt-sigusr2+)
    (cl-cc/runtime::rt-dispatch-os-signal +rt-sigusr2+)
    (assert-= 1 count)
    (assert-null (gethash +rt-sigusr2+ cl-cc/runtime::*rt-signal-handlers*))))

(deftest signals-process-pending-dispatches-deferred
  "Deferred (pending) signals are dispatched on process-pending-signals."
  (let ((cl-cc/runtime::*rt-signal-handlers* (make-hash-table))
        (cl-cc/runtime::*pending-signals* nil)
        (cl-cc/runtime::*rt-signal-mask* nil)
        (fired nil))
    (setf (gethash +rt-sigusr1+ cl-cc/runtime::*rt-signal-handlers*)
          (list (cl-cc/runtime::make-rt-signal-handler
                 :signal +rt-sigusr1+
                 :function (lambda (sig) (push sig fired)))))
    (cl-cc/runtime::%rt-record-pending-signal +rt-sigusr1+)
    (let ((processed (rt-process-pending-signals)))
      (assert-equal (list +rt-sigusr1+) processed)
      (assert-equal (list +rt-sigusr1+) fired))))

(deftest signals-process-pending-skips-masked
  "A masked pending signal is not dispatched."
  (let ((cl-cc/runtime::*rt-signal-handlers* (make-hash-table))
        (cl-cc/runtime::*pending-signals* nil)
        (cl-cc/runtime::*rt-signal-mask* (list +rt-sigusr1+))
        (fired nil))
    (setf (gethash +rt-sigusr1+ cl-cc/runtime::*rt-signal-handlers*)
          (list (cl-cc/runtime::make-rt-signal-handler
                 :signal +rt-sigusr1+
                 :function (lambda (sig) (push sig fired)))))
    (cl-cc/runtime::%rt-record-pending-signal +rt-sigusr1+)
    (rt-process-pending-signals)
    (assert-null fired)))

(deftest signals-run-shutdown-hooks
  "Shutdown hooks are each called with the signal number."
  (let* ((cl-cc/runtime::*shutdown-hooks* nil)
         (seen nil))
    (push (lambda (sig) (push sig seen)) cl-cc/runtime::*shutdown-hooks*)
    (assert-true (cl-cc/runtime::%rt-run-shutdown-hooks +rt-sigterm+))
    (assert-equal (list +rt-sigterm+) seen)))

;;; ── remove-signal-handler ─────────────────────────────────────────

(deftest signals-remove-handler
  "rt-remove-signal-handler unlinks a specific handler from its signal list."
  (let* ((cl-cc/runtime::*rt-signal-handlers* (make-hash-table))
         (h (cl-cc/runtime::make-rt-signal-handler
             :signal +rt-sigusr1+ :function (lambda (s) (declare (ignore s))))))
    (setf (gethash +rt-sigusr1+ cl-cc/runtime::*rt-signal-handlers*) (list h))
    (assert-true (cl-cc/runtime::rt-remove-signal-handler h))
    (assert-null (gethash +rt-sigusr1+ cl-cc/runtime::*rt-signal-handlers*))))

;;; ── Native disposition (benign signals, restored) ─────────────────

(deftest signals-set-and-get-default-ignore
  "rt-set-signal-handler stores :default / :ignore and get reflects them."
  (let ((cl-cc/runtime::*rt-signal-handlers* (make-hash-table))
        (cl-cc/runtime::*rt-sigaction-installed* (make-hash-table)))
    (unwind-protect
         (progn
           (assert-eq :ignore (rt-set-signal-handler +rt-sigusr1+ :ignore))
           (assert-eq :ignore (rt-get-signal-handler +rt-sigusr1+))
           (assert-eq :default (rt-set-signal-handler +rt-sigusr1+ :default))
           (assert-eq :default (rt-get-signal-handler +rt-sigusr1+)))
      (sb-sys:enable-interrupt +rt-sigusr1+ :default))))

(deftest signals-set-function-handler-is-looked-up
  "A user function installed via rt-set-signal-handler is returned by get."
  (let ((cl-cc/runtime::*rt-signal-handlers* (make-hash-table))
        (cl-cc/runtime::*rt-sigaction-installed* (make-hash-table))
        (fn (lambda (sig) (declare (ignore sig)) :ok)))
    (unwind-protect
         (progn
           (rt-set-signal-handler +rt-sigusr2+ fn)
           (assert-eq fn (rt-get-signal-handler +rt-sigusr2+)))
      (sb-sys:enable-interrupt +rt-sigusr2+ :default))))

(deftest signals-get-unset-defaults
  "A signal with no handler installed reports :default."
  (let ((cl-cc/runtime::*rt-signal-handlers* (make-hash-table))
        (cl-cc/runtime::*rt-sigaction-installed* (make-hash-table)))
    (assert-eq :default (rt-get-signal-handler +rt-sigwinch+))))

(deftest signals-install-handler-records-metadata
  "rt-install-signal-handler returns a handler struct registered for the signal."
  (let ((cl-cc/runtime::*rt-signal-handlers* (make-hash-table))
        (cl-cc/runtime::*rt-sigaction-installed* (make-hash-table)))
    (unwind-protect
         (let ((h (cl-cc/runtime::rt-install-signal-handler
                   +rt-sigusr1+ (lambda (s) (declare (ignore s))))))
           (assert-= +rt-sigusr1+ (cl-cc/runtime::rt-signal-handler-signal h))
           (assert-true (member h (gethash +rt-sigusr1+
                                           cl-cc/runtime::*rt-signal-handlers*))))
      (sb-sys:enable-interrupt +rt-sigusr1+ :default))))

(deftest signals-with-signal-handler-restores
  "rt-with-signal-handler installs a handler for BODY and restores afterward."
  (let ((cl-cc/runtime::*rt-signal-handlers* (make-hash-table))
        (cl-cc/runtime::*rt-sigaction-installed* (make-hash-table)))
    (unwind-protect
         (progn
           (rt-with-signal-handler (+rt-sigusr2+ :ignore)
             (assert-eq :ignore (rt-get-signal-handler +rt-sigusr2+)))
           ;; restored to the prior disposition (:default) after the body
           (assert-eq :default (rt-get-signal-handler +rt-sigusr2+)))
      (sb-sys:enable-interrupt +rt-sigusr2+ :default))))

(deftest signals-clear-handlers
  "rt-clear-signal-handlers empties the registry (optionally per-signal)."
  (let ((cl-cc/runtime::*rt-signal-handlers* (make-hash-table)))
    (setf (gethash +rt-sigusr1+ cl-cc/runtime::*rt-signal-handlers*) (list :x)
          (gethash +rt-sigusr2+ cl-cc/runtime::*rt-signal-handlers*) (list :y))
    (rt-clear-signal-handlers +rt-sigusr1+)
    (assert-null (gethash +rt-sigusr1+ cl-cc/runtime::*rt-signal-handlers*))
    (assert-true (gethash +rt-sigusr2+ cl-cc/runtime::*rt-signal-handlers*))
    (rt-clear-signal-handlers)
    (assert-null (gethash +rt-sigusr2+ cl-cc/runtime::*rt-signal-handlers*))))
