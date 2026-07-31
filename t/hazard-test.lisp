;;;; t/hazard-test.lisp — hazard pointers (src/hazard.lisp).
;;;; These functions share process-global registries keyed by thread, so each
;;;; test calls rt-hp-init first to reset the world.
(in-package :cl-cc-runtime/test)

(describe
  "hazard pointer registration and protection"
  (it
    "protecting an object marks it protected across a scan"
    (rt-hp-init)
    (rt-hp-register-thread 4)
    (let ((a 101)
          (b 202))
      (rt-hp-protect 0 a)
      (expect (rt-hp-scan (list a b)) :to-equal (list b))
      (expect (member a (rt-hp-all-protected)) :not :to-be nil))
    (rt-hp-unregister-thread))
  (it
    "clearing a slot releases protection"
    (rt-hp-init)
    (rt-hp-register-thread 4)
    (let ((a 11))
      (rt-hp-protect 2 a)
      (expect (rt-hp-scan (list a)) :to-equal '())
      (rt-hp-clear 2)
      (expect (rt-hp-scan (list a)) :to-equal (list a)))
    (rt-hp-unregister-thread))
  (it
    "clear-all releases every slot"
    (rt-hp-init)
    (rt-hp-register-thread 4)
    (rt-hp-protect 0 1)
    (rt-hp-protect 1 2)
    (rt-hp-protect 2 3)
    (rt-hp-clear-all)
    (expect (rt-hp-all-protected) :to-equal '())
    (rt-hp-unregister-thread))
  (it
    "protect on an unregistered thread is a no-op that returns the index"
    (rt-hp-init)
    (expect (rt-hp-protect 0 :x) :to-be 0)
    (expect (rt-hp-all-protected) :to-equal '()))
  (it
    "an out-of-range slot index clamps to the last slot without error"
    (rt-hp-init)
    (rt-hp-register-thread 2)
    (expect (rt-hp-protect 99 :clamped) :to-be 99)
    (expect (member :clamped (rt-hp-all-protected)) :not :to-be nil)
    (rt-hp-unregister-thread))
  (it-property
    "scan returns exactly the unprotected candidates in order"
    ((raw (gen-list (gen-integer :min 0 :max 300) :max-length 20))
      (k (gen-integer :min 0 :max 20)))
    (rt-hp-init)
    (let* ((all (remove-duplicates raw))
           (kk (min k (length all)))
           (protected (subseq all 0 kk)))
      (rt-hp-register-thread (max 1 (length all)))
      (loop for obj in protected
            for i from 0
            do (rt-hp-protect i obj))
      (expect (rt-hp-scan all) :to-equal (subseq all kk))
      (rt-hp-unregister-thread))))

(describe "hazard pointer retirement and reclamation"
  (it "rt-hp-retire below threshold returns the list untouched"
    (rt-hp-init)
    (let ((freed '()))
      (let ((result (rt-hp-retire (list 1 2) (lambda (o) (push o freed)) 5)))
        (expect result :to-equal (list 1 2))
        (expect freed :to-equal '()))))

  (it "rt-hp-retire at threshold frees unprotected and keeps protected"
    (rt-hp-init)
    (rt-hp-register-thread 2)
    (rt-hp-protect 0 7)                      ; 7 is protected, 8 is not
    (let ((freed '()))
      (let ((remaining (rt-hp-retire (list 7 8) (lambda (o) (push o freed)) 2)))
        (expect remaining :to-equal (list 7))
        (expect freed :to-equal (list 8))))
    (rt-hp-unregister-thread))

  (it "rt-hp-reclaim frees a thread's unprotected retired objects and counts them"
    (let ((freed '()))
      (rt-hp-init (lambda (o) (push o freed)))
      (rt-hp-register-thread 2)
      (rt-hp-protect 0 7)
      (rt-hp-retire-object 7 :threshold 1000)
      (rt-hp-retire-object 8 :threshold 1000)
      (expect (rt-hp-reclaim) :to-be 1)
      (expect (and (member 8 freed) t) :to-be-truthy)
      (expect (member 7 freed) :to-be-null)
      ;; 7 remains retired; once unprotected it too can be reclaimed.
      (rt-hp-clear 0)
      (expect (rt-hp-reclaim) :to-be 1)
      (expect (and (member 7 freed) t) :to-be-truthy)
      (rt-hp-unregister-thread)))

  (it "set-threshold clamps to a minimum of 1"
    (expect (rt-hp-set-threshold 10) :to-be 10)
    (expect (rt-hp-set-threshold -5) :to-be 1))

  (it "rt-hp-init returns t"
    (expect (rt-hp-init) :to-be-truthy)))
