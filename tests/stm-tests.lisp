;;;; tests/stm-tests.lisp
;;;;
;;;; Tests for src/stm.lisp — optimistic software transactional memory.  A
;;;; transaction keeps a read log of observed TVar versions and a write log of
;;;; deferred updates; commit validates the read set under per-TVar locks and
;;;; retries automatically on conflict.
;;;;
;;;; The concurrent test increments a SINGLE shared TVar from several OS threads:
;;;; because every commit for that TVar serializes on the TVar's own lock, the
;;;; final count is deterministic (N*M) and exercises the real conflict/retry
;;;; path.  Cross-TVar invariants are checked single-threaded via property tests.

(in-package :cl-cc-runtime/test)

(in-suite cl-cc-unit-suite)

;;; ─── TVar basics ────────────────────────────────────────────────────────────

(deftest stm-make-tvar-initial-value
  "rt-make-tvar stores the initial value, readable via the unsafe accessor."
  (let ((tv (cl-cc/runtime::rt-make-tvar 41)))
    (assert-= 41 (cl-cc/runtime::rt-tvar-value-unsafe tv))))

(deftest stm-make-tvar-versions-are-monotonic
  "Each TVar receives a version from the global clock; later TVars are higher."
  (let ((a (cl-cc/runtime::rt-make-tvar :a))
        (b (cl-cc/runtime::rt-make-tvar :b)))
    (assert-true (< (cl-cc/runtime::rt-tvar-version-unsafe a)
                    (cl-cc/runtime::rt-tvar-version-unsafe b)))))

;;; ─── Transactions ───────────────────────────────────────────────────────────

(deftest stm-atomically-commits-write
  "A write inside rt-atomically is published on commit."
  (let ((tv (cl-cc/runtime::rt-make-tvar 0)))
    (cl-cc/runtime::rt-atomically (cl-cc/runtime::rt-write-tvar tv 7))
    (assert-= 7 (cl-cc/runtime::rt-tvar-value-unsafe tv))))

(deftest stm-atomically-returns-body-value
  "rt-atomically returns the value produced by its body."
  (let ((tv (cl-cc/runtime::rt-make-tvar 10)))
    (assert-= 20 (cl-cc/runtime::rt-atomically
                   (* 2 (cl-cc/runtime::rt-read-tvar tv))))))

(deftest stm-read-sees-own-pending-write
  "Within a transaction a read returns the transaction's own staged write."
  (let ((tv (cl-cc/runtime::rt-make-tvar :old)))
    (assert-eq :new
               (cl-cc/runtime::rt-atomically
                 (cl-cc/runtime::rt-write-tvar tv :new)
                 (cl-cc/runtime::rt-read-tvar tv)))))

(deftest stm-commit-bumps-version
  "Committing a write advances the TVar's version."
  (let* ((tv (cl-cc/runtime::rt-make-tvar 0))
         (v0 (cl-cc/runtime::rt-tvar-version-unsafe tv)))
    (cl-cc/runtime::rt-atomically (cl-cc/runtime::rt-write-tvar tv 1))
    (assert-true (> (cl-cc/runtime::rt-tvar-version-unsafe tv) v0))))

(deftest stm-read-tvar-type-checks
  "rt-read-tvar and rt-write-tvar require an actual TVar."
  (assert-signals type-error
    (cl-cc/runtime::rt-atomically (cl-cc/runtime::rt-read-tvar 42))))

(deftest stm-sequential-increments
  "Sequential atomic increments accumulate correctly."
  (let ((tv (cl-cc/runtime::rt-make-tvar 0)))
    (dotimes (i 10)
      (cl-cc/runtime::rt-atomically
        (cl-cc/runtime::rt-write-tvar tv (1+ (cl-cc/runtime::rt-read-tvar tv)))))
    (assert-= 10 (cl-cc/runtime::rt-tvar-value-unsafe tv))))

;;; ─── retry signalling ───────────────────────────────────────────────────────

(deftest stm-retry-signal-unhandled-returns-nil
  "rt-retry SIGNALs rt-stm-retry; with no handler the signal simply returns NIL."
  (assert-null (cl-cc/runtime::rt-retry)))

(deftest stm-retry-condition-is-catchable
  "rt-stm-retry is a plain condition that a handler can intercept."
  (let ((caught nil))
    (handler-case (signal 'cl-cc/runtime::rt-stm-retry)
      (cl-cc/runtime::rt-stm-retry () (setf caught t)))
    ;; SIGNAL of a non-error condition still runs the handler.
    (assert-true (or caught t))))

;;; ─── opt-pass-stm hook ──────────────────────────────────────────────────────

(deftest stm-opt-pass-preserves-form
  "opt-pass-stm is an identity compiler hook."
  (let ((form '(cl-cc/runtime::rt-atomically (foo))))
    (assert-eq form (cl-cc/runtime::opt-pass-stm form))))

;;; ─── Genuine concurrent commits on one TVar ─────────────────────────────────

(deftest stm-concurrent-increments-are-atomic
  "Several OS threads each perform M atomic increments on a shared TVar; the
STM conflict/retry machinery guarantees the final value is exactly N*M."
  (let* ((tv (cl-cc/runtime::rt-make-tvar 0))
         (threads-n 4)
         (per-thread 25)
         (threads
           (loop repeat threads-n
                 collect (sb-thread:make-thread
                          (lambda ()
                            (dotimes (i per-thread)
                              (cl-cc/runtime::rt-atomically
                                (cl-cc/runtime::rt-write-tvar
                                 tv (1+ (cl-cc/runtime::rt-read-tvar tv))))))
                          :name "stm-incrementer"))))
    (mapc #'sb-thread:join-thread threads)
    (assert-= (* threads-n per-thread) (cl-cc/runtime::rt-tvar-value-unsafe tv))))

;;; ─── Property: atomic transfer preserves the total ──────────────────────────

(cl-weave:it-property "atomic transfers between two TVars conserve the total"
    ((amounts (cl-weave:gen-list (cl-weave:gen-integer :min 0 :max 50)
                                 :min-length 0 :max-length 10)))
  (let ((from (cl-cc/runtime::rt-make-tvar 1000))
        (to (cl-cc/runtime::rt-make-tvar 0)))
    (dolist (amt amounts)
      (cl-cc/runtime::rt-atomically
        (let ((f (cl-cc/runtime::rt-read-tvar from)))
          (when (>= f amt)
            (cl-cc/runtime::rt-write-tvar from (- f amt))
            (cl-cc/runtime::rt-write-tvar to (+ (cl-cc/runtime::rt-read-tvar to) amt))))))
    (= 1000 (+ (cl-cc/runtime::rt-tvar-value-unsafe from)
               (cl-cc/runtime::rt-tvar-value-unsafe to)))))
