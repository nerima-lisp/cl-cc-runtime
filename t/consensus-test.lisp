(in-package :cl-cc-runtime/test)

;;;; Characterization tests for src/consensus.lisp (Raft consensus node).
;;;;
;;;; These pin the CURRENT behavior of the hand-written Raft implementation so
;;;; that any later refactor can be verified against them. They deliberately
;;;; reach into internal helpers (via cl-cc/runtime::) where the exported API is
;;;; not enough to exercise a single transition in isolation, mirroring the
;;;; style of t/deadlock-test.lisp.
;;; ── Election ──────────────────────────────────────────────────────
(it-sequential
  "A lone node wins its own election immediately (majority of 1)."
  (let* ((cluster (rt-make-raft-cluster '("n1")))
         (node (gethash "n1" (rt-raft-cluster-nodes cluster))))
    (expect (rt-raft-start-election node cluster) :to-be-truthy)
    (expect (rt-raft-node-state node) :to-equal +raft-leader+)
    (expect (rt-raft-node-current-term node) :to-equal 1)
    (expect (rt-raft-node-voted-for node) :to-equal "n1")
    (expect (rt-raft-cluster-leader-id cluster) :to-equal "n1")))

(it-sequential
  "A candidate collects votes from all peers and becomes leader."
  (let* ((cluster (rt-make-raft-cluster '("n1" "n2" "n3")))
         (n1 (gethash "n1" (rt-raft-cluster-nodes cluster))))
    (expect (rt-raft-start-election n1 cluster) :to-be-truthy)
    (expect (rt-raft-node-state n1) :to-equal +raft-leader+)
    (expect (length (cl-cc/runtime::rt-raft-node-votes-received n1)) :to-equal 3)
    (expect (rt-raft-cluster-leader-id cluster) :to-equal "n1")))

(it-sequential
  "A candidate that discovers a peer with a higher term steps down to follower
and does not win."
  (let* ((cluster (rt-make-raft-cluster '("n1" "n2")))
         (n1 (gethash "n1" (rt-raft-cluster-nodes cluster)))
         (n2 (gethash "n2" (rt-raft-cluster-nodes cluster))))
    (setf (rt-raft-node-current-term n2) 5)
    (expect (rt-raft-start-election n1 cluster) :to-be-null)
    (expect (rt-raft-node-state n1) :to-equal +raft-follower+)
    (expect (rt-raft-node-current-term n1) :to-equal 5)))

(it-sequential
  "A follower whose election timer exceeds its timeout starts an election."
  (let* ((cluster (rt-make-raft-cluster '("n1")))
         (node (gethash "n1" (rt-raft-cluster-nodes cluster))))
    (setf (rt-raft-node-election-timeout node) 5
          (rt-raft-node-election-timer node) 0
          (rt-raft-node-state node) +raft-follower+)
    (rt-raft-tick node cluster 10)
    (expect (rt-raft-node-state node) :to-equal +raft-leader+)))

;;; ── RequestVote ───────────────────────────────────────────────────
(it-sequential
  "A fresh voter grants its vote to a candidate with an equally-empty log."
  (let ((candidate (rt-make-raft-node "c"))
        (voter (rt-make-raft-node "v")))
    (setf (rt-raft-node-current-term candidate) 1)
    (expect (rt-raft-request-vote candidate voter) :to-be-truthy)
    (expect (rt-raft-node-voted-for voter) :to-equal "c")
    (expect (rt-raft-node-current-term voter) :to-equal 1)))

(it-sequential
  "After voting once, a voter refuses a different candidate in the same term."
  (let ((c1 (rt-make-raft-node "c1"))
        (c2 (rt-make-raft-node "c2"))
        (voter (rt-make-raft-node "v")))
    (setf (rt-raft-node-current-term c1) 1
          (rt-raft-node-current-term c2) 1)
    (expect (rt-raft-request-vote c1 voter) :to-be-truthy)
    (expect (rt-raft-request-vote c2 voter) :to-be-null)
    (expect (rt-raft-node-voted-for voter) :to-equal "c1")))

(it-sequential
  "A candidate whose term is behind the voter's is rejected, voter untouched."
  (let ((candidate (rt-make-raft-node "c"))
        (voter (rt-make-raft-node "v")))
    (setf (rt-raft-node-current-term candidate) 1
          (rt-raft-node-current-term voter) 3)
    (expect (rt-raft-request-vote candidate voter) :to-be-null)
    (expect (rt-raft-node-current-term voter) :to-equal 3)
    (expect (rt-raft-node-voted-for voter) :to-be-null)))

(it-sequential
  "Seeing a higher candidate term forces the voter back to follower."
  (let ((candidate (rt-make-raft-node "c"))
        (voter (rt-make-raft-node "v")))
    (setf (rt-raft-node-current-term candidate) 3
          (rt-raft-node-current-term voter) 1
          (rt-raft-node-state voter) +raft-leader+)
    (expect (rt-raft-request-vote candidate voter) :to-be-truthy)
    (expect (rt-raft-node-state voter) :to-equal +raft-follower+)
    (expect (rt-raft-node-current-term voter) :to-equal 3)))

(it-sequential
  "A candidate with a shorter/older log than the voter is denied."
  (let ((candidate (rt-make-raft-node "c"))
        (voter (rt-make-raft-node "v")))
    (setf (rt-raft-node-current-term candidate) 1
          (rt-raft-node-current-term voter) 1)
    (push
      (make-rt-raft-entry :term 1 :index 1 :command 'x)
      (rt-raft-node-log voter))
    (expect (rt-raft-request-vote candidate voter) :to-be-null)
    (expect (rt-raft-node-voted-for voter) :to-be-null)))

;;; ── Leader initialization ─────────────────────────────────────────
(it-sequential
  "On becoming leader, next-index is last-log-index+1 and match-index is 0 for
peers (self match-index is the last log index)."
  (let* ((cluster (rt-make-raft-cluster '("n1" "n2")))
         (n1 (gethash "n1" (rt-raft-cluster-nodes cluster))))
    (rt-raft-become-leader n1 cluster)
    (expect (rt-raft-node-state n1) :to-equal +raft-leader+)
    (expect (gethash "n2" (cl-cc/runtime::rt-raft-node-next-index n1)) :to-equal 1)
    (expect (gethash "n2" (cl-cc/runtime::rt-raft-node-match-index n1)) :to-equal 0)
    (expect (gethash "n1" (cl-cc/runtime::rt-raft-node-match-index n1)) :to-equal 0)))

;;; ── Log replication & commit ──────────────────────────────────────
(it-sequential
  "A proposed value replicates to a majority and advances the commit index."
  (let* ((cluster (rt-make-raft-cluster '("n1" "n2" "n3")))
         (n1 (gethash "n1" (rt-raft-cluster-nodes cluster))))
    (rt-raft-start-election n1 cluster)
    (expect (rt-raft-propose cluster 42) :to-equal 42)
    (expect (rt-raft-node-commit-index n1) :to-equal 1)
    (expect (cl-cc/runtime::%rt-raft-last-log-index n1) :to-equal 1)
    (expect
      (>= (gethash "n2" (cl-cc/runtime::rt-raft-node-match-index n1)) 1)
      :to-be-truthy)))

(it-sequential
  "A committed entry is applied to both the leader and follower state machines."
  (let* ((cluster (rt-make-raft-cluster '("n1" "n2" "n3")))
         (n1 (gethash "n1" (rt-raft-cluster-nodes cluster)))
         (n2 (gethash "n2" (rt-raft-cluster-nodes cluster))))
    (rt-raft-start-election n1 cluster)
    (rt-raft-propose cluster 'hello)
    (expect (rt-raft-node-state-machine n1) :to-equal '(hello))
    (expect (rt-raft-node-commit-index n2) :to-equal 1)
    (expect (rt-raft-node-state-machine n2) :to-equal '(hello))))

(it-sequential
  "Proposing to a cluster with no leader signals an error."
  (let ((cluster (rt-make-raft-cluster '("n1" "n2" "n3"))))
    (signals error (rt-raft-propose cluster 99))))

(it-sequential "advance-commit only commits an entry from the leader's current term even when
a majority has replicated it." (let* ((cluster (rt-make-raft-cluster '("n1" "n2" "n3")))
         (n1 (gethash "n1" (rt-raft-cluster-nodes cluster))))
    (rt-raft-start-election n1 cluster) ; term 1
    ;; Stale entry from an earlier term, replicated to a majority.
    (push (make-rt-raft-entry :term 0 :index 1 :command 'old)
          (rt-raft-node-log n1))
    (setf (gethash "n1" (cl-cc/runtime::rt-raft-node-match-index n1)) 1
          (gethash "n2" (cl-cc/runtime::rt-raft-node-match-index n1)) 1
          (gethash "n3" (cl-cc/runtime::rt-raft-node-match-index n1)) 1)
    (rt-raft-advance-commit n1 cluster)
    (expect (rt-raft-node-commit-index n1) :to-equal 0)))

;;; ── AppendEntries guards ──────────────────────────────────────────
(it-sequential
  "A follower rejects AppendEntries from a leader whose term is behind its own."
  (let* ((cluster (rt-make-raft-cluster '("n1" "n2")))
         (leader (gethash "n1" (rt-raft-cluster-nodes cluster)))
         (follower (gethash "n2" (rt-raft-cluster-nodes cluster))))
    (setf (rt-raft-node-current-term leader) 1
          (rt-raft-node-current-term follower) 5)
    (expect
      (cl-cc/runtime::%rt-raft-handle-append-entries
        leader
        follower
        cluster
        nil
        0
        0
        0)
      :to-be-null)
    (expect (rt-raft-node-current-term follower) :to-equal 5)))

(it-sequential "A follower rejects AppendEntries whose prev-log-term does not match its log." (let* ((cluster (rt-make-raft-cluster '("n1" "n2")))
         (leader (gethash "n1" (rt-raft-cluster-nodes cluster)))
         (follower (gethash "n2" (rt-raft-cluster-nodes cluster))))
    (setf (rt-raft-node-current-term leader) 2
          (rt-raft-node-current-term follower) 2)
    (push (make-rt-raft-entry :term 1 :index 1 :command 'a)
          (rt-raft-node-log follower))
    ;; Claim prev-index 1 had term 2, but the follower stored term 1.
    (expect (cl-cc/runtime::%rt-raft-handle-append-entries
                  leader follower cluster nil 1 2 0) :to-be-null)))

;;; ── Step-down ─────────────────────────────────────────────────────
(it-sequential
  "step-down adopts a strictly higher term and reverts state to follower."
  (let* ((cluster (rt-make-raft-cluster '("n1")))
         (node (gethash "n1" (rt-raft-cluster-nodes cluster))))
    (setf (rt-raft-node-state node) +raft-leader+
          (rt-raft-node-current-term node) 2
          (rt-raft-node-voted-for node) "n1"
          (rt-raft-cluster-leader-id cluster) "n1")
    (cl-cc/runtime::%rt-raft-step-down node 5 cluster)
    (expect (rt-raft-node-state node) :to-equal +raft-follower+)
    (expect (rt-raft-node-current-term node) :to-equal 5)
    (expect (rt-raft-node-voted-for node) :to-be-null)
    (expect (rt-raft-cluster-leader-id cluster) :to-be-null)))

(it-sequential
  "step-down with a non-higher term still resets state but keeps the term."
  (let* ((cluster (rt-make-raft-cluster '("n1")))
         (node (gethash "n1" (rt-raft-cluster-nodes cluster))))
    (setf (rt-raft-node-state node) +raft-candidate+
          (rt-raft-node-current-term node) 5)
    (cl-cc/runtime::%rt-raft-step-down node 3 cluster)
    (expect (rt-raft-node-state node) :to-equal +raft-follower+)
    (expect (rt-raft-node-current-term node) :to-equal 5)))

;;; ── Apply / snapshot ──────────────────────────────────────────────
(it-sequential
  "rt-raft-apply threads committed commands through a supplied reducer."
  (let ((node (rt-make-raft-node "n")))
    (push (make-rt-raft-entry :term 1 :index 1 :command 10) (rt-raft-node-log node))
    (push (make-rt-raft-entry :term 1 :index 2 :command 5) (rt-raft-node-log node))
    (setf (rt-raft-node-commit-index node) 2
          (rt-raft-node-state-machine node) 0)
    (rt-raft-apply
      node
      (lambda (state command)
        (+ (or state 0) command)))
    (expect (rt-raft-node-state-machine node) :to-equal 15)
    (expect (rt-raft-node-last-applied node) :to-equal 2)))

(it-sequential
  "rt-raft-snapshot returns entries oldest-first regardless of storage order."
  (let ((node (rt-make-raft-node "n")))
    (push
      (make-rt-raft-entry :term 1 :index 1 :command 'first)
      (rt-raft-node-log node))
    (push
      (make-rt-raft-entry :term 1 :index 2 :command 'second)
      (rt-raft-node-log node))
    (let ((snap (rt-raft-snapshot node)))
      (expect (length snap) :to-equal 2)
      (expect (rt-raft-entry-command (first snap)) :to-be 'first)
      (expect (rt-raft-entry-command (second snap)) :to-be 'second))))
