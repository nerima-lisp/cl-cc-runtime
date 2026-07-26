(in-package :cl-cc-runtime/test)
(in-suite cl-cc-unit-suite)

;;;; Characterization tests for src/consensus.lisp (Raft consensus node).
;;;;
;;;; These pin the CURRENT behavior of the hand-written Raft implementation so
;;;; that any later refactor can be verified against them. They deliberately
;;;; reach into internal helpers (via cl-cc/runtime::) where the exported API is
;;;; not enough to exercise a single transition in isolation, mirroring the
;;;; style of t/deadlock-test.lisp.

;;; ── Election ──────────────────────────────────────────────────────

(deftest raft-single-node-election-becomes-leader
  "A lone node wins its own election immediately (majority of 1)."
  (let* ((cluster (rt-make-raft-cluster '("n1")))
         (node (gethash "n1" (rt-raft-cluster-nodes cluster))))
    (assert-true (rt-raft-start-election node cluster))
    (assert-= +raft-leader+ (rt-raft-node-state node))
    (assert-= 1 (rt-raft-node-current-term node))
    (assert-equal "n1" (rt-raft-node-voted-for node))
    (assert-equal "n1" (rt-raft-cluster-leader-id cluster))))

(deftest raft-three-node-election-wins-majority
  "A candidate collects votes from all peers and becomes leader."
  (let* ((cluster (rt-make-raft-cluster '("n1" "n2" "n3")))
         (n1 (gethash "n1" (rt-raft-cluster-nodes cluster))))
    (assert-true (rt-raft-start-election n1 cluster))
    (assert-= +raft-leader+ (rt-raft-node-state n1))
    (assert-= 3 (length (cl-cc/runtime::rt-raft-node-votes-received n1)))
    (assert-equal "n1" (rt-raft-cluster-leader-id cluster))))

(deftest raft-election-steps-down-when-peer-has-higher-term
  "A candidate that discovers a peer with a higher term steps down to follower
and does not win."
  (let* ((cluster (rt-make-raft-cluster '("n1" "n2")))
         (n1 (gethash "n1" (rt-raft-cluster-nodes cluster)))
         (n2 (gethash "n2" (rt-raft-cluster-nodes cluster))))
    (setf (rt-raft-node-current-term n2) 5)
    (assert-null (rt-raft-start-election n1 cluster))
    (assert-= +raft-follower+ (rt-raft-node-state n1))
    (assert-= 5 (rt-raft-node-current-term n1))))

(deftest raft-tick-triggers-election-on-timeout
  "A follower whose election timer exceeds its timeout starts an election."
  (let* ((cluster (rt-make-raft-cluster '("n1")))
         (node (gethash "n1" (rt-raft-cluster-nodes cluster))))
    (setf (rt-raft-node-election-timeout node) 5
          (rt-raft-node-election-timer node) 0
          (rt-raft-node-state node) +raft-follower+)
    (rt-raft-tick node cluster 10)
    (assert-= +raft-leader+ (rt-raft-node-state node))))

;;; ── RequestVote ───────────────────────────────────────────────────

(deftest raft-request-vote-granted-for-empty-logs
  "A fresh voter grants its vote to a candidate with an equally-empty log."
  (let ((candidate (rt-make-raft-node "c"))
        (voter (rt-make-raft-node "v")))
    (setf (rt-raft-node-current-term candidate) 1)
    (assert-true (rt-raft-request-vote candidate voter))
    (assert-equal "c" (rt-raft-node-voted-for voter))
    (assert-= 1 (rt-raft-node-current-term voter))))

(deftest raft-request-vote-rejects-second-candidate-same-term
  "After voting once, a voter refuses a different candidate in the same term."
  (let ((c1 (rt-make-raft-node "c1"))
        (c2 (rt-make-raft-node "c2"))
        (voter (rt-make-raft-node "v")))
    (setf (rt-raft-node-current-term c1) 1
          (rt-raft-node-current-term c2) 1)
    (assert-true (rt-raft-request-vote c1 voter))
    (assert-null (rt-raft-request-vote c2 voter))
    (assert-equal "c1" (rt-raft-node-voted-for voter))))

(deftest raft-request-vote-rejects-stale-term
  "A candidate whose term is behind the voter's is rejected, voter untouched."
  (let ((candidate (rt-make-raft-node "c"))
        (voter (rt-make-raft-node "v")))
    (setf (rt-raft-node-current-term candidate) 1
          (rt-raft-node-current-term voter) 3)
    (assert-null (rt-raft-request-vote candidate voter))
    (assert-= 3 (rt-raft-node-current-term voter))
    (assert-null (rt-raft-node-voted-for voter))))

(deftest raft-request-vote-steps-voter-down-on-higher-term
  "Seeing a higher candidate term forces the voter back to follower."
  (let ((candidate (rt-make-raft-node "c"))
        (voter (rt-make-raft-node "v")))
    (setf (rt-raft-node-current-term candidate) 3
          (rt-raft-node-current-term voter) 1
          (rt-raft-node-state voter) +raft-leader+)
    (assert-true (rt-raft-request-vote candidate voter))
    (assert-= +raft-follower+ (rt-raft-node-state voter))
    (assert-= 3 (rt-raft-node-current-term voter))))

(deftest raft-request-vote-rejects-when-voter-log-more-current
  "A candidate with a shorter/older log than the voter is denied."
  (let ((candidate (rt-make-raft-node "c"))
        (voter (rt-make-raft-node "v")))
    (setf (rt-raft-node-current-term candidate) 1
          (rt-raft-node-current-term voter) 1)
    (push (make-rt-raft-entry :term 1 :index 1 :command 'x)
          (rt-raft-node-log voter))
    (assert-null (rt-raft-request-vote candidate voter))
    (assert-null (rt-raft-node-voted-for voter))))

;;; ── Leader initialization ─────────────────────────────────────────

(deftest raft-become-leader-initializes-index-tables
  "On becoming leader, next-index is last-log-index+1 and match-index is 0 for
peers (self match-index is the last log index)."
  (let* ((cluster (rt-make-raft-cluster '("n1" "n2")))
         (n1 (gethash "n1" (rt-raft-cluster-nodes cluster))))
    (rt-raft-become-leader n1 cluster)
    (assert-= +raft-leader+ (rt-raft-node-state n1))
    (assert-= 1 (gethash "n2" (cl-cc/runtime::rt-raft-node-next-index n1)))
    (assert-= 0 (gethash "n2" (cl-cc/runtime::rt-raft-node-match-index n1)))
    (assert-= 0 (gethash "n1" (cl-cc/runtime::rt-raft-node-match-index n1)))))

;;; ── Log replication & commit ──────────────────────────────────────

(deftest raft-propose-replicates-to-majority-and-commits
  "A proposed value replicates to a majority and advances the commit index."
  (let* ((cluster (rt-make-raft-cluster '("n1" "n2" "n3")))
         (n1 (gethash "n1" (rt-raft-cluster-nodes cluster))))
    (rt-raft-start-election n1 cluster)
    (assert-= 42 (rt-raft-propose cluster 42))
    (assert-= 1 (rt-raft-node-commit-index n1))
    (assert-= 1 (cl-cc/runtime::%rt-raft-last-log-index n1))
    (assert-true (>= (gethash "n2" (cl-cc/runtime::rt-raft-node-match-index n1)) 1))))

(deftest raft-propose-applies-committed-entry-to-state-machine
  "A committed entry is applied to both the leader and follower state machines."
  (let* ((cluster (rt-make-raft-cluster '("n1" "n2" "n3")))
         (n1 (gethash "n1" (rt-raft-cluster-nodes cluster)))
         (n2 (gethash "n2" (rt-raft-cluster-nodes cluster))))
    (rt-raft-start-election n1 cluster)
    (rt-raft-propose cluster 'hello)
    (assert-equal '(hello) (rt-raft-node-state-machine n1))
    (assert-= 1 (rt-raft-node-commit-index n2))
    (assert-equal '(hello) (rt-raft-node-state-machine n2))))

(deftest raft-propose-without-leader-signals-error
  "Proposing to a cluster with no leader signals an error."
  (let ((cluster (rt-make-raft-cluster '("n1" "n2" "n3"))))
    (assert-signals error (rt-raft-propose cluster 99))))

(deftest raft-advance-commit-requires-current-term-entry
  "advance-commit only commits an entry from the leader's current term even when
a majority has replicated it."
  (let* ((cluster (rt-make-raft-cluster '("n1" "n2" "n3")))
         (n1 (gethash "n1" (rt-raft-cluster-nodes cluster))))
    (rt-raft-start-election n1 cluster) ; term 1
    ;; Stale entry from an earlier term, replicated to a majority.
    (push (make-rt-raft-entry :term 0 :index 1 :command 'old)
          (rt-raft-node-log n1))
    (setf (gethash "n1" (cl-cc/runtime::rt-raft-node-match-index n1)) 1
          (gethash "n2" (cl-cc/runtime::rt-raft-node-match-index n1)) 1
          (gethash "n3" (cl-cc/runtime::rt-raft-node-match-index n1)) 1)
    (rt-raft-advance-commit n1 cluster)
    (assert-= 0 (rt-raft-node-commit-index n1))))

;;; ── AppendEntries guards ──────────────────────────────────────────

(deftest raft-append-entries-rejects-stale-leader-term
  "A follower rejects AppendEntries from a leader whose term is behind its own."
  (let* ((cluster (rt-make-raft-cluster '("n1" "n2")))
         (leader (gethash "n1" (rt-raft-cluster-nodes cluster)))
         (follower (gethash "n2" (rt-raft-cluster-nodes cluster))))
    (setf (rt-raft-node-current-term leader) 1
          (rt-raft-node-current-term follower) 5)
    (assert-null (cl-cc/runtime::%rt-raft-handle-append-entries
                  leader follower cluster nil 0 0 0))
    (assert-= 5 (rt-raft-node-current-term follower))))

(deftest raft-append-entries-rejects-log-mismatch
  "A follower rejects AppendEntries whose prev-log-term does not match its log."
  (let* ((cluster (rt-make-raft-cluster '("n1" "n2")))
         (leader (gethash "n1" (rt-raft-cluster-nodes cluster)))
         (follower (gethash "n2" (rt-raft-cluster-nodes cluster))))
    (setf (rt-raft-node-current-term leader) 2
          (rt-raft-node-current-term follower) 2)
    (push (make-rt-raft-entry :term 1 :index 1 :command 'a)
          (rt-raft-node-log follower))
    ;; Claim prev-index 1 had term 2, but the follower stored term 1.
    (assert-null (cl-cc/runtime::%rt-raft-handle-append-entries
                  leader follower cluster nil 1 2 0))))

;;; ── Step-down ─────────────────────────────────────────────────────

(deftest raft-step-down-reverts-to-follower-on-higher-term
  "step-down adopts a strictly higher term and reverts state to follower."
  (let* ((cluster (rt-make-raft-cluster '("n1")))
         (node (gethash "n1" (rt-raft-cluster-nodes cluster))))
    (setf (rt-raft-node-state node) +raft-leader+
          (rt-raft-node-current-term node) 2
          (rt-raft-node-voted-for node) "n1"
          (rt-raft-cluster-leader-id cluster) "n1")
    (cl-cc/runtime::%rt-raft-step-down node 5 cluster)
    (assert-= +raft-follower+ (rt-raft-node-state node))
    (assert-= 5 (rt-raft-node-current-term node))
    (assert-null (rt-raft-node-voted-for node))
    (assert-null (rt-raft-cluster-leader-id cluster))))

(deftest raft-step-down-keeps-term-when-not-higher
  "step-down with a non-higher term still resets state but keeps the term."
  (let* ((cluster (rt-make-raft-cluster '("n1")))
         (node (gethash "n1" (rt-raft-cluster-nodes cluster))))
    (setf (rt-raft-node-state node) +raft-candidate+
          (rt-raft-node-current-term node) 5)
    (cl-cc/runtime::%rt-raft-step-down node 3 cluster)
    (assert-= +raft-follower+ (rt-raft-node-state node))
    (assert-= 5 (rt-raft-node-current-term node))))

;;; ── Apply / snapshot ──────────────────────────────────────────────

(deftest raft-apply-uses-custom-apply-function
  "rt-raft-apply threads committed commands through a supplied reducer."
  (let ((node (rt-make-raft-node "n")))
    (push (make-rt-raft-entry :term 1 :index 1 :command 10)
          (rt-raft-node-log node))
    (push (make-rt-raft-entry :term 1 :index 2 :command 5)
          (rt-raft-node-log node))
    (setf (rt-raft-node-commit-index node) 2
          (rt-raft-node-state-machine node) 0)
    (rt-raft-apply node (lambda (state command) (+ (or state 0) command)))
    (assert-= 15 (rt-raft-node-state-machine node))
    (assert-= 2 (rt-raft-node-last-applied node))))

(deftest raft-snapshot-returns-log-in-forward-order
  "rt-raft-snapshot returns entries oldest-first regardless of storage order."
  (let ((node (rt-make-raft-node "n")))
    (push (make-rt-raft-entry :term 1 :index 1 :command 'first)
          (rt-raft-node-log node))
    (push (make-rt-raft-entry :term 1 :index 2 :command 'second)
          (rt-raft-node-log node))
    (let ((snap (rt-raft-snapshot node)))
      (assert-= 2 (length snap))
      (assert-eq 'first (rt-raft-entry-command (first snap)))
      (assert-eq 'second (rt-raft-entry-command (second snap))))))
