;;;; t/portable-test.lisp — Coverage for src/portable.lisp
;;;;
;;;; Self-host portability lock facades that map onto sync.lisp's mutex API.

(in-package :cl-cc-runtime/test)

(in-suite cl-cc-unit-suite)

(deftest portable-make-lock-returns-mutex
  "rt-make-lock builds an rt-mutex, optionally carrying a name."
  (let ((lk (cl-cc/runtime:rt-make-lock "portable-lock")))
    (assert-true (cl-cc/runtime::rt-mutex-p lk))
    (assert-equal "portable-lock" (cl-cc/runtime::rt-mutex-name lk))))

(deftest portable-lock-unlock-cycle
  "rt-lock acquires and rt-unlock releases; both report success."
  (let ((lk (cl-cc/runtime:rt-make-lock)))
    (assert-true (cl-cc/runtime:rt-lock lk))
    (assert-true (cl-cc/runtime:rt-unlock lk))
    ;; Re-acquiring after release must succeed again.
    (assert-true (cl-cc/runtime:rt-lock lk))
    (cl-cc/runtime:rt-unlock lk)))

(deftest portable-try-lock-on-free-lock
  "rt-try-lock succeeds without blocking on an uncontended lock."
  (let ((lk (cl-cc/runtime:rt-make-lock)))
    (assert-true (cl-cc/runtime:rt-try-lock lk))
    (cl-cc/runtime:rt-unlock lk)))

(deftest portable-with-lock-returns-body-value
  "rt-with-lock evaluates its body under the lock and returns the last form."
  (let ((lk (cl-cc/runtime:rt-make-lock)))
    (assert-= 42 (cl-cc/runtime:rt-with-lock (lk) (+ 40 2)))
    ;; The lock must be free afterward, so a fresh acquisition succeeds.
    (assert-true (cl-cc/runtime:rt-try-lock lk))
    (cl-cc/runtime:rt-unlock lk)))

(deftest portable-with-lock-releases-on-nonlocal-exit
  "rt-with-lock releases the lock even when the body performs a non-local exit."
  (let ((lk (cl-cc/runtime:rt-make-lock)))
    (block escape
      (cl-cc/runtime:rt-with-lock (lk)
        (return-from escape nil)))
    (assert-true (cl-cc/runtime:rt-try-lock lk))
    (cl-cc/runtime:rt-unlock lk)))
