;;;; tests/mvcc-tests.lisp — multi-version concurrency control (src/mvcc.lisp).
(in-package :cl-cc-runtime/test)

(describe "mvcc direct (non-transactional) access"
  (it "an empty variable reads as nil"
    (expect (rt-mvcc-read (rt-make-mvcc-var)) :to-be-null))

  (it "make-mvcc-var seeds an initial version"
    (expect (rt-mvcc-read (rt-make-mvcc-var 5)) :to-be 5))

  (it "direct writes are immediately visible and newest wins"
    (let ((v (rt-make-mvcc-var)))
      (cl-cc/runtime::rt-mvcc-write v 10)
      (expect (rt-mvcc-read v) :to-be 10)
      (cl-cc/runtime::rt-mvcc-write v 20)
      (expect (rt-mvcc-read v) :to-be 20))))

(describe "mvcc snapshot isolation"
  (it "a transaction reads its snapshot, not later external writes"
    (let ((v (rt-make-mvcc-var 1)))
      (let ((tx (cl-cc/runtime::rt-mvcc-begin)))
        (cl-cc/runtime::rt-mvcc-write v 2)          ; external, after the snapshot
        (expect (rt-mvcc-read v tx) :to-be 1)
        (expect (rt-mvcc-read v) :to-be 2))))

  (it "a transaction reads its own uncommitted writes"
    (let ((v (rt-make-mvcc-var 1)))
      (let ((tx (cl-cc/runtime::rt-mvcc-begin)))
        (cl-cc/runtime::rt-mvcc-write v 99 tx)
        (expect (rt-mvcc-read v tx) :to-be 99)      ; own write visible to itself
        (expect (rt-mvcc-read v) :to-be 1))))       ; not yet globally visible

  (it-property "a snapshot read is stable regardless of later writes"
      ((initial (gen-integer :min -100 :max 100))
       (updates (gen-list (gen-integer :min -100 :max 100) :max-length 10)))
    (let ((v (rt-make-mvcc-var initial)))
      (let ((tx (cl-cc/runtime::rt-mvcc-begin)))
        (dolist (u updates) (cl-cc/runtime::rt-mvcc-write v u))
        (expect (rt-mvcc-read v tx) :to-be initial)
        (expect (rt-mvcc-read v)
                :to-be (if updates (car (last updates)) initial))))))

(describe "mvcc transaction lifecycle"
  (it "commit publishes a transaction's writes"
    (let ((v (rt-make-mvcc-var 1)))
      (let ((tx (cl-cc/runtime::rt-mvcc-begin)))
        (cl-cc/runtime::rt-mvcc-write v 42 tx)
        (cl-cc/runtime::rt-mvcc-commit tx)
        (expect (rt-mvcc-read v) :to-be 42))))

  (it "abort discards a transaction's writes"
    (let ((v (rt-make-mvcc-var 1)))
      (let ((tx (cl-cc/runtime::rt-mvcc-begin)))
        (cl-cc/runtime::rt-mvcc-write v 42 tx)
        (cl-cc/runtime::rt-mvcc-abort tx)
        (expect (rt-mvcc-read v) :to-be 1))))

  (it "rt-with-mvcc-transaction commits on normal exit"
    (let ((v (rt-make-mvcc-var 1)))
      (rt-with-mvcc-transaction ()
        (cl-cc/runtime::rt-mvcc-write v 7))
      (expect (rt-mvcc-read v) :to-be 7)))

  (it "rt-with-mvcc-transaction rolls back when the body signals"
    (let ((v (rt-make-mvcc-var 1)))
      (expect (lambda ()
                (rt-with-mvcc-transaction ()
                  (cl-cc/runtime::rt-mvcc-write v 7)
                  (error "boom")))
              :to-throw 'simple-error)
      (expect (rt-mvcc-read v) :to-be 1))))

(describe "mvcc compaction"
  (it "compact drops versions older than the given timestamp"
    (let ((v (rt-make-mvcc-var)))
      (cl-cc/runtime::rt-mvcc-write v 1)
      (cl-cc/runtime::rt-mvcc-write v 2)
      (cl-cc/runtime::rt-mvcc-write v 3)
      (rt-mvcc-compact v cl-cc/runtime::*rt-mvcc-global-time*)
      (expect (rt-mvcc-read v) :to-be 3)
      (expect (length (cl-cc/runtime::rt-mvcc-var-versions v)) :to-be 1))))

;; All direct writes to one variable serialize on that variable's mutex, so the
;; version chain must grow by exactly one entry per write even under contention.
(describe "mvcc under concurrency"
  (it "concurrent direct writers add exactly one version per write"
    (let* ((v (rt-make-mvcc-var 0))
           (nthreads 4) (per 200)
           (threads (loop repeat nthreads
                          collect (sb-thread:make-thread
                                   (lambda ()
                                     (dotimes (i per)
                                       (cl-cc/runtime::rt-mvcc-write v i)))))))
      (dolist (th threads) (sb-thread:join-thread th))
      (expect (length (cl-cc/runtime::rt-mvcc-var-versions v))
              :to-be (1+ (* nthreads per)))
      (expect (integerp (rt-mvcc-read v)) :to-be-truthy))))
