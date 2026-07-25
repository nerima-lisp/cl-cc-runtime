;;;; tests/ebr-tests.lisp — epoch-based reclamation (src/ebr.lisp).
;;;; Uses process-global epoch state; each test resets via rt-ebr-init.
(in-package :cl-cc-runtime/test)

(describe "ebr epoch bookkeeping"
  (it "current-local registers on first use and stays stable"
    (rt-ebr-init)
    (let ((l1 (rt-ebr-current-local)))
      (expect l1 :not :to-be nil)
      (expect (rt-ebr-current-local) :to-be l1)))

  (it "register then unregister removes the thread local"
    (rt-ebr-init)
    (rt-ebr-register-thread)
    (expect (hash-table-count cl-cc/runtime::*ebr-thread-locals*) :to-be 1)
    (rt-ebr-unregister-thread)
    (expect (hash-table-count cl-cc/runtime::*ebr-thread-locals*) :to-be 0))

  (it "rt-with-ebr-critical increments then restores the critical counter"
    (rt-ebr-init)
    (let ((local (rt-ebr-register-thread)) (ran nil))
      (rt-with-ebr-critical (local)
        (setf ran t)
        (expect (cl-cc/runtime::rt-ebr-local-in-critical local) :to-be 1))
      (expect ran :to-be-truthy)
      (expect (cl-cc/runtime::rt-ebr-local-in-critical local) :to-be 0)))

  (it "cannot advance while a thread is critical in a stale epoch"
    (rt-ebr-init)
    (let ((local (rt-ebr-register-thread)))
      (expect (cl-cc/runtime::rt-ebr-can-advance-p) :to-be-truthy)
      (rt-ebr-enter local)                       ; local still epoch 0
      (cl-cc/runtime::rt-ebr-advance-epoch)      ; global -> 1
      (expect (cl-cc/runtime::rt-ebr-can-advance-p) :to-be-null)
      (expect (cl-cc/runtime::rt-ebr-advance-epoch) :to-be-null)
      (rt-ebr-leave local)                       ; local epoch catches up to 1
      (expect (cl-cc/runtime::rt-ebr-can-advance-p) :to-be-truthy)))

  (it "retire routes objects into the bucket for the local epoch"
    (rt-ebr-init)
    (let ((local (rt-ebr-register-thread)))
      (rt-ebr-retire local :a)
      (expect (cl-cc/runtime::rt-ebr-local-retired-0 local) :to-equal '(:a))
      (cl-cc/runtime::rt-ebr-advance-epoch)      ; global -> 1
      (rt-ebr-enter local) (rt-ebr-leave local)  ; local epoch -> 1
      (rt-ebr-retire local :b)
      (expect (cl-cc/runtime::rt-ebr-local-retired-1 local) :to-equal '(:b)))))

(describe "ebr grace-period reclamation"
  (it "reclaims a retired object only after the epoch cycles past it"
    (let ((freed '()))
      (rt-ebr-init (lambda (o) (push o freed)))
      (let ((local (rt-ebr-register-thread)))
        (rt-ebr-retire local :a)                     ; bucket 0
        (expect (cl-cc/runtime::rt-ebr-reclaim local) :to-be 0) ; safe bucket 1
        (cl-cc/runtime::rt-ebr-advance-epoch)        ; global 1
        (expect (cl-cc/runtime::rt-ebr-reclaim local) :to-be 0) ; safe bucket 2
        (cl-cc/runtime::rt-ebr-advance-epoch)        ; global 2
        (expect (cl-cc/runtime::rt-ebr-reclaim local) :to-be 1) ; safe bucket 0
        (expect freed :to-equal '(:a)))))

  (it "rt-ebr-collect advances the epoch and reclaims"
    (let ((freed '()))
      (rt-ebr-init (lambda (o) (push o freed)))
      (let ((local (rt-ebr-register-thread)))
        (rt-ebr-retire local :x)                     ; bucket 0
        (rt-ebr-collect local)                       ; global 0->1
        (rt-ebr-collect local)                       ; global 1->2, frees bucket 0
        (expect freed :to-equal '(:x))))))

;; Genuine multi-threaded exercise. Locals are registered under the EBR mutex
;; (the same lock advance-epoch holds), so the shared registry is never mutated
;; concurrently with iteration. After every worker joins, no thread is critical,
;; so cycling the epoch reclaims every retired object exactly once.
(describe "ebr under concurrency"
  (it "reclaims every object retired by concurrent workers"
    (let ((freed 0) (lock (sb-thread:make-mutex)))
      (rt-ebr-init (lambda (o) (declare (ignore o))
                     (sb-thread:with-mutex (lock) (incf freed))))
      (let* ((nthreads 4) (per 200)
             (workers
               (loop repeat nthreads
                     collect (sb-thread:make-thread
                              (lambda ()
                                (let ((local (cl-cc/runtime::rt-with-mutex (cl-cc/runtime::*ebr-mutex*)
                                               (rt-ebr-register-thread))))
                                  (dotimes (i per)
                                    (rt-with-ebr-critical (local)
                                      (rt-ebr-retire local i))
                                    (cl-cc/runtime::rt-ebr-advance-epoch))))))))
        (dolist (w workers) (sb-thread:join-thread w))
        (dotimes (i 5) (rt-ebr-collect))
        (expect freed :to-be (* nthreads per))))))
