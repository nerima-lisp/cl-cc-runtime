;;;; t/portable-test.lisp — Coverage for src/portable.lisp
;;;;
;;;; Self-host portability lock facades that map onto sync.lisp's mutex API.
(in-package :cl-cc-runtime/test)

(it-sequential
  "rt-make-lock builds an rt-mutex, optionally carrying a name."
  (let ((lk (cl-cc/runtime:rt-make-lock "portable-lock")))
    (expect (cl-cc/runtime::rt-mutex-p lk) :to-be-truthy)
    (expect (cl-cc/runtime::rt-mutex-name lk) :to-equal "portable-lock")))

(it-sequential "rt-lock acquires and rt-unlock releases; both report success." (let ((lk (cl-cc/runtime:rt-make-lock)))
    (expect (cl-cc/runtime:rt-lock lk) :to-be-truthy)
    (expect (cl-cc/runtime:rt-unlock lk) :to-be-truthy)
    ;; Re-acquiring after release must succeed again.
    (expect (cl-cc/runtime:rt-lock lk) :to-be-truthy)
    (cl-cc/runtime:rt-unlock lk)))

(it-sequential
  "rt-try-lock succeeds without blocking on an uncontended lock."
  (let ((lk (cl-cc/runtime:rt-make-lock)))
    (expect (cl-cc/runtime:rt-try-lock lk) :to-be-truthy)
    (cl-cc/runtime:rt-unlock lk)))

(it-sequential "rt-with-lock evaluates its body under the lock and returns the last form." (let ((lk (cl-cc/runtime:rt-make-lock)))
    (expect (cl-cc/runtime:rt-with-lock (lk) (+ 40 2)) :to-equal 42)
    ;; The lock must be free afterward, so a fresh acquisition succeeds.
    (expect (cl-cc/runtime:rt-try-lock lk) :to-be-truthy)
    (cl-cc/runtime:rt-unlock lk)))

(it-sequential
  "rt-with-lock releases the lock even when the body performs a non-local exit."
  (let ((lk (cl-cc/runtime:rt-make-lock)))
    (block escape
      (cl-cc/runtime:rt-with-lock (lk) (return-from escape nil)))
    (expect (cl-cc/runtime:rt-try-lock lk) :to-be-truthy)
    (cl-cc/runtime:rt-unlock lk)))
