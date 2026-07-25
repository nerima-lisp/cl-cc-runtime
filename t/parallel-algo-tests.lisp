(in-package :cl-cc-runtime/test)
(in-suite cl-cc-unit-suite)

;;;; Tests for src/parallel-algo.lisp — fork/join parallel primitives.
;;;;
;;;; The parallel branches drive the cooperative scheduler, so the parallel-path
;;;; tests rt-scheduler-init first and lower the split threshold. Correctness is
;;;; checked as an invariant (sorted permutation / scan == fold) via property
;;;; tests, independent of whether the sequential or parallel branch ran.

;;; ── Threshold + fork-join ─────────────────────────────────────────

(deftest parallel-threshold-predicate
  "rt-parallel-p is true exactly when size reaches the threshold."
  (let ((cl-cc/runtime::*rt-parallel-threshold* 8))
    (assert-false (cl-cc/runtime::rt-parallel-p 7))
    (assert-true (cl-cc/runtime::rt-parallel-p 8))
    (assert-true (cl-cc/runtime::rt-parallel-p 9))))

(deftest parallel-fork-join-without-scheduler-combines
  "With no scheduler present fork-join simply combines both thunks' values."
  (let ((cl-cc/runtime::*rt-global-scheduler* nil))
    (assert-= 7 (cl-cc/runtime::rt-fork-join (lambda () 3) (lambda () 4) #'+))))

(deftest parallel-fork-join-with-scheduler-combines
  "With a scheduler, fork-join still returns the combined result."
  (rt-scheduler-init)
  (assert-equal '(3 . 4)
                (cl-cc/runtime::rt-fork-join (lambda () 3) (lambda () 4) #'cons)))

;;; ── Sort ──────────────────────────────────────────────────────────

(deftest parallel-sort-sequential-list
  "Below threshold, list sort returns a sorted list."
  (assert-equal '(1 2 3 4 5) (rt-parallel-sort '(3 1 4 5 2) #'<)))

(deftest parallel-sort-vector-in-place
  "Vector sort returns the same (now sorted) sequence."
  (let ((v (vector 5 3 8 1 9 2)))
    (assert-equalp #(1 2 3 5 8 9) (rt-parallel-sort v #'<))))

(deftest parallel-sort-with-key
  "Sort honors a key extractor."
  (assert-equal '((1 :a) (2 :b) (3 :c))
                (rt-parallel-sort '((3 :c) (1 :a) (2 :b)) #'< :key #'first)))

(deftest parallel-sort-parallel-path
  "With a low threshold and a scheduler, the fork/join merge path sorts too."
  (rt-scheduler-init)
  (let ((cl-cc/runtime::*rt-parallel-threshold* 2))
    (assert-equal '(1 2 3 4 5 6 7)
                  (rt-parallel-sort '(4 2 7 1 6 3 5) #'<))))

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

(deftest parallel-scan-exclusive
  "Exclusive scan stores the accumulator before folding each element."
  (assert-equalp #(0 1 3) (cl-cc/runtime::rt-parallel-scan #(1 2 3) #'+ 0)))

(deftest parallel-scan-inclusive
  "Inclusive scan stores the accumulator after folding each element."
  (assert-equalp #(1 3 6) (cl-cc/runtime::rt-parallel-scan #(1 2 3) #'+ 0 :inclusive t)))

(deftest parallel-prefix-scan-is-inclusive
  "rt-parallel-prefix-scan is the inclusive form of scan."
  (assert-equalp #(1 3 6) (rt-parallel-prefix-scan #(1 2 3) #'+ 0)))

(cl-weave:it-property "inclusive scan last element equals the fold"
    ((items (cl-weave:gen-list (cl-weave:gen-integer :min 0 :max 20)
                               :min-length 1 :max-length 10)))
  (let* ((vec (coerce items 'vector))
         (scan (rt-parallel-prefix-scan vec #'+ 0)))
    (cl-weave:expect (aref scan (1- (length scan)))
                     :to-be (reduce #'+ items :initial-value 0))))

(deftest parallel-reduce-without-initial-value
  "Reduce without :iv folds the sequence directly."
  (assert-= 10 (rt-parallel-reduce #'+ '(1 2 3 4))))

(deftest parallel-reduce-with-initial-value
  "Reduce with :iv seeds the fold."
  (assert-= 20 (rt-parallel-reduce #'+ '(1 2 3 4) :iv 10)))

;;; ── Map / for ─────────────────────────────────────────────────────

(deftest parallel-map-sequential
  "Below threshold, map applies FN elementwise like mapcar."
  (assert-equal '(2 3 4) (rt-parallel-map #'1+ '(1 2 3))))

(deftest parallel-map-parallel-path
  "With a scheduler and low threshold the spawned map returns FN of each item."
  (rt-scheduler-init)
  (let ((cl-cc/runtime::*rt-parallel-threshold* 1))
    (assert-equal '(1 4 9 16)
                  (rt-parallel-map (lambda (x) (* x x)) '(1 2 3 4)))))

(deftest parallel-for-runs-body-over-range
  "parallel-for spawns one task per index and runs each body once."
  (rt-scheduler-init)
  (let ((seen (make-array 4 :initial-element nil)))
    (rt-parallel-for 0 4 (lambda (i) (setf (aref seen i) t)))
    (assert-true (every #'identity seen))))

(deftest parallel-algo-init-resets-threshold
  "Init restores the default split threshold and reports success."
  (let ((cl-cc/runtime::*rt-parallel-threshold* 7))
    (assert-true (rt-parallel-algo-init))
    (assert-= 1024 cl-cc/runtime::*rt-parallel-threshold*)))
