(in-package :cl-cc-runtime/test)

;;;; Tests for src/parallel-algo.lisp — fork/join parallel primitives.
;;;;
;;;; The parallel branches drive the cooperative scheduler, so the parallel-path
;;;; tests rt-scheduler-init first and lower the split threshold. Correctness is
;;;; checked as an invariant (sorted permutation / scan == fold) via property
;;;; tests, independent of whether the sequential or parallel branch ran.
;;; ── Threshold + fork-join ─────────────────────────────────────────
(it-sequential
  "rt-parallel-p is true exactly when size reaches the threshold."
  (let ((cl-cc/runtime::*rt-parallel-threshold* 8))
    (expect (cl-cc/runtime::rt-parallel-p 7) :to-be-falsy)
    (expect (cl-cc/runtime::rt-parallel-p 8) :to-be-truthy)
    (expect (cl-cc/runtime::rt-parallel-p 9) :to-be-truthy)))

(it-sequential
  "With no scheduler present fork-join simply combines both thunks' values."
  (let ((cl-cc/runtime::*rt-global-scheduler* nil))
    (expect
      (cl-cc/runtime::rt-fork-join
        (lambda ()
          3)
        (lambda ()
          4)
        #'+)
      :to-equal
      7)))

(it-sequential
  "With a scheduler, fork-join still returns the combined result."
  (rt-scheduler-init)
  (expect
    (cl-cc/runtime::rt-fork-join
      (lambda ()
        3)
      (lambda ()
        4)
      #'cons)
    :to-equal
    '(3 . 4)))

;;; ── Sort ──────────────────────────────────────────────────────────
(it-sequential
  "Below threshold, list sort returns a sorted list."
  (expect (rt-parallel-sort '(3 1 4 5 2) #'<) :to-equal '(1 2 3 4 5)))

(it-sequential
  "Vector sort returns the same (now sorted) sequence."
  (let ((v (vector 5 3 8 1 9 2)))
    (expect (rt-parallel-sort v #'<) :to-equalp #(1 2 3 5 8 9))))

(it-sequential
  "Sort honors a key extractor."
  (expect
    (rt-parallel-sort '((3 :c) (1 :a) (2 :b)) #'< :key #'first)
    :to-equal
    '((1 :a) (2 :b) (3 :c))))

(it-sequential
  "With a low threshold and a scheduler, the fork/join merge path sorts too."
  (rt-scheduler-init)
  (let ((cl-cc/runtime::*rt-parallel-threshold* 2))
    (expect (rt-parallel-sort '(4 2 7 1 6 3 5) #'<) :to-equal '(1 2 3 4 5 6 7))))

(cl-weave:it-property "parallel sort yields a sorted permutation"
    ((items (cl-weave:gen-list (cl-weave:gen-integer :min -30 :max 30)
                               :max-length 12)))
  (let ((sorted (rt-parallel-sort (copy-list items) #'<)))
    ;; Ordered ...
    (cl-weave:expect (apply #'<= (or sorted '(0))) :to-be-truthy)
    ;; ... and a permutation of the input.
    (cl-weave:expect (sort (copy-list sorted) #'<)
                     :to-equal (sort (copy-list items) #'<))))

;;; ── Scan / reduce ─────────────────────────────────────────────────
(it-sequential
  "Exclusive scan stores the accumulator before folding each element."
  (expect (cl-cc/runtime::rt-parallel-scan #(1 2 3) #'+ 0) :to-equalp #(0 1 3)))

(it-sequential
  "Inclusive scan stores the accumulator after folding each element."
  (expect
    (cl-cc/runtime::rt-parallel-scan #(1 2 3) #'+ 0 :inclusive t)
    :to-equalp
    #(1 3 6)))

(it-sequential
  "rt-parallel-prefix-scan is the inclusive form of scan."
  (expect (rt-parallel-prefix-scan #(1 2 3) #'+ 0) :to-equalp #(1 3 6)))

(cl-weave:it-property
  "inclusive scan last element equals the fold"
  ((items
      (cl-weave:gen-list
        (cl-weave:gen-integer :min 0 :max 20)
        :min-length
        1
        :max-length
        10)))
  (let* ((vec (coerce items 'vector))
         (scan (rt-parallel-prefix-scan vec #'+ 0)))
    (cl-weave:expect
      (aref scan (1- (length scan)))
      :to-be
      (reduce #'+ items :initial-value 0))))

(it-sequential
  "Reduce without :iv folds the sequence directly."
  (expect (rt-parallel-reduce #'+ '(1 2 3 4)) :to-equal 10))

(it-sequential
  "Reduce with :iv seeds the fold."
  (expect (rt-parallel-reduce #'+ '(1 2 3 4) :iv 10) :to-equal 20))

;;; ── Map / for ─────────────────────────────────────────────────────
(it-sequential
  "Below threshold, map applies FN elementwise like mapcar."
  (expect (rt-parallel-map #'1+ '(1 2 3)) :to-equal '(2 3 4)))

(it-sequential
  "With a scheduler and low threshold the spawned map returns FN of each item."
  (rt-scheduler-init)
  (let ((cl-cc/runtime::*rt-parallel-threshold* 1))
    (expect
      (rt-parallel-map
        (lambda (x)
          (* x x))
        '(1 2 3 4))
      :to-equal
      '(1 4 9 16))))

(it-sequential
  "parallel-for spawns one task per index and runs each body once."
  (rt-scheduler-init)
  (let ((seen (make-array 4 :initial-element nil)))
    (rt-parallel-for
      0
      4
      (lambda (i)
        (setf (aref seen i) t)))
    (expect (every #'identity seen) :to-be-truthy)))

(it-sequential
  "Init restores the default split threshold and reports success."
  (let ((cl-cc/runtime::*rt-parallel-threshold* 7))
    (expect (rt-parallel-algo-init) :to-be-truthy)
    (expect cl-cc/runtime::*rt-parallel-threshold* :to-equal 1024)))
