(in-package :cl-cc-runtime/test)
(in-suite cl-cc-unit-suite)

;;;; Tests for src/cluster.lisp — cluster membership registry + remote refs.
;;;;
;;;; These exercise the global membership hash table, so every test re-inits the
;;;; cluster via rt-cluster-init to avoid cross-test leakage. Struct accessors on
;;;; rt-cluster-node / rt-remote-actor-ref are unexported, hence the
;;;; cl-cc/runtime:: qualifications.

(deftest cluster-init-registers-local-node
  "rt-cluster-init installs the local node as :up and queryable by id."
  (assert-true (rt-cluster-init :id "self" :host "10.0.0.1" :port 7000))
  (assert-eq :up (rt-cluster-query-node-status "self"))
  (let ((local cl-cc/runtime::*rt-cluster-local*))
    (assert-equal "self" (cl-cc/runtime::rt-cluster-node-id local))
    (assert-equal "10.0.0.1" (cl-cc/runtime::rt-cluster-node-host local))
    (assert-= 7000 (cl-cc/runtime::rt-cluster-node-port local))))

(deftest cluster-init-clears-previous-membership
  "Re-initializing drops nodes from a prior cluster generation."
  (rt-cluster-init :id "n1")
  (rt-cluster-join "n2" "127.0.0.1" 1)
  (assert-eq :up (rt-cluster-query-node-status "n2"))
  (rt-cluster-init :id "fresh")
  (assert-null (rt-cluster-query-node-status "n2"))
  (assert-null (rt-cluster-query-node-status "n1")))

(deftest cluster-join-adds-up-node
  "A joined node is stored with :up status and its address."
  (rt-cluster-init :id "n1")
  (rt-cluster-join "n2" "192.168.1.5" 9999)
  (assert-eq :up (rt-cluster-query-node-status "n2"))
  (let ((n (gethash "n2" cl-cc/runtime::*rt-cluster-nodes*)))
    (assert-equal "192.168.1.5" (cl-cc/runtime::rt-cluster-node-host n))
    (assert-= 9999 (cl-cc/runtime::rt-cluster-node-port n))))

(deftest cluster-leave-removes-node
  "Leaving removes a node so its status becomes unknown (NIL)."
  (rt-cluster-init :id "n1")
  (rt-cluster-join "n2" "127.0.0.1" 1)
  (rt-cluster-leave "n2")
  (assert-null (rt-cluster-query-node-status "n2")))

(deftest cluster-query-unknown-node-returns-nil
  "Querying a node that never joined returns NIL."
  (rt-cluster-init :id "n1")
  (assert-null (rt-cluster-query-node-status "ghost")))

(deftest cluster-remote-send-is-noop-stub
  "The portable remote-send stub returns NIL without error."
  (assert-null (rt-remote-send (rt-make-remote-ref "n2" "actor-7") '(:ping))))

(deftest cluster-make-remote-ref-carries-ids
  "A remote actor ref preserves its node and actor identifiers."
  (let ((ref (rt-make-remote-ref "node-9" "actor-3")))
    (assert-equal "node-9" (cl-cc/runtime::rt-remote-actor-ref-node-id ref))
    (assert-equal "actor-3" (cl-cc/runtime::rt-remote-actor-ref-actor-id ref))))
