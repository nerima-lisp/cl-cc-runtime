;;;; packages/runtime/src/gc-major-mark.lisp — Concurrent-mark configuration,
;;;; mode control, and the mark-queue lock. The tri-color mark work itself is
;;;; in gc-mark-work.lisp.
;;;
;;; Contains:
;;;   - %gc-sweep-old-space — sweep dead objects from old generation
;;;   - rt-gc-major-collect — tri-color mark-and-sweep full GC
;;;   - rt-gc-stats — GC statistics plist
;;;
;;; Minor GC (Cheney copying), write barrier, allocation, and root registration
;;; are in gc.lisp (loads before).
;;;
;;; Load order: after gc.lisp.
(in-package :cl-cc/runtime)

(defparameter *rt-concurrent-gc-enabled-p* nil
  "When true, major collection enters :major-gc-concurrent state.")

(define-symbol-macro *concurrent-gc-enabled* *rt-concurrent-gc-enabled-p*)

(defparameter *rt-concurrent-gc-write-barrier-mode* :satb
  "Concurrent-GC barrier mode (:satb or :incremental-update).")

(defparameter *rt-concurrent-gc-stw-phases* '(:initial-mark :final-remark)
  "STW phase model used when concurrent GC mode is enabled.")

(defparameter *rt-concurrent-gc-mutator-assist-p* t
  "When true, mutators are expected to assist concurrent marking progress.")

(defparameter *rt-concurrent-mark-thread* nil
  "Host thread object for the active concurrent mark worker, or NIL.

FR-339 foundation: SBCL hosts may run phase-2 marking on SB-THREAD while mutators
continue through SATB pre-write barriers. Implementations without threads drain
the same grey queue synchronously while preserving the four-phase protocol.")

(defparameter *rt-concurrent-sweep-thread* nil
  "Host thread object for a concurrent old-space sweep worker, or NIL.")

;;; FR-088: Incremental GC Marking — bounded mark steps interleaved with mutator work; 4-phase
;;; protocol (initial-mark, incremental-mark, final-remark, sweep)
(defparameter *gc-incremental-mark-enabled* nil
  "When true, major GC exposes its mark phase as bounded incremental steps.

RT-GC-MAJOR-COLLECT is organized as:
  Phase 1: initial mark (STW root snapshot)
  Phase 2: incremental mark (RT-GC-INCREMENTAL-MARK-STEP drains grey work)
  Phase 3: final remark (STW SATB drain)
   Phase 4: sweep (STW in this foundation implementation).")

;;; FR-468: GC Copy Order as Cache Warm-Up — biases free-list toward blocks adjacent to hot
;;; objects for cache-friendly placement
(defparameter *gc-profile-guided-placement* nil
  "When true, bias old-space free-list order toward blocks adjacent to hot objects.

This is the FR-468 foundation hook.  The current mark-sweep collector does not
move live objects; it reorders reclaimed blocks so future old-space allocation
prefers holes near hot survivors, preserving a cache-friendly placement path for
the future compacting collector.")

;;; FR-340: Concurrent Sweeping — sweeps old space on-demand during allocation; lazy sweep with
;;; page-level granularity
(defparameter *gc-lazy-sweep-enabled* nil
  "When true, major GC defers old-space sweeping and allocation sweeps pages on demand.")

(defparameter *gc-max-pause-ms* 200
  "Maximum target stop-the-world GC pause in milliseconds before SLO accounting fires.")

(defvar *rt-gc-incremental-mark-queues* (make-hash-table :test #'eq)
  "Heap -> grey queue for incremental major-GC marking.")

(defun %rt-gc-mark-make-mutex (name)
  "Create an optional host mutex without reader-time SB-THREAD dependency."
  (let ((make-mutex (%rt-resolve-sb-thread-function "MAKE-MUTEX")))
    (and make-mutex (ignore-errors (funcall make-mutex :name name)))))

(defvar *rt-gc-incremental-mark-queues-lock*
  (%rt-gc-mark-make-mutex "gc-incremental-mark-queues")
  "Mutex protecting *rt-gc-incremental-mark-queues* from concurrent access.")

(defmacro with-gc-mark-queue-locked (() &body body)
  "Execute BODY while holding the incremental mark-queue hash-table mutex."
  `(%rt-with-optional-grab-release-lock (*rt-gc-incremental-mark-queues-lock*) ,@body))

(defun rt-gc-configure-concurrent-mode (&key enabled-p write-barrier stw-phases mutator-assist-p)
  "Configure concurrent-GC runtime mode and return current settings plist."
  (when (not (null enabled-p))
    (setf *rt-concurrent-gc-enabled-p* enabled-p))
  (when write-barrier
    (setf *rt-concurrent-gc-write-barrier-mode* write-barrier))
  (when stw-phases
    (setf *rt-concurrent-gc-stw-phases* (copy-list stw-phases)))
  (when (not (null mutator-assist-p))
    (setf *rt-concurrent-gc-mutator-assist-p* mutator-assist-p))
  (list :enabled-p *rt-concurrent-gc-enabled-p*
        :write-barrier *rt-concurrent-gc-write-barrier-mode*
        :stw-phases (copy-list *rt-concurrent-gc-stw-phases*)
        :mutator-assist-p *rt-concurrent-gc-mutator-assist-p*))

(defun rt-gc-concurrent-assist (heap &key (budget 16))
  "Perform a bounded mutator-assist step during concurrent major GC.

Drains current SATB entries into the incremental grey queue, marks up to BUDGET
grey objects, and returns the number of grey objects processed."
  (if (or (not *rt-concurrent-gc-enabled-p*)
          (not *rt-concurrent-gc-mutator-assist-p*)
          (not (eq (rt-heap-gc-state heap) :major-gc-concurrent)))
      0
      (let ((queue-cell (cons (with-gc-mark-queue-locked ()
                                (gethash heap *rt-gc-incremental-mark-queues*))
                              nil)))
        (%rt-gc-drain-satb-to-grey heap queue-cell)
        (with-gc-mark-queue-locked ()
          (setf (gethash heap *rt-gc-incremental-mark-queues*) (car queue-cell)))
        (destructuring-bind (status &optional processed)
            (rt-gc-incremental-mark-step heap budget)
          (declare (ignore status))
          (or processed 0)))))
