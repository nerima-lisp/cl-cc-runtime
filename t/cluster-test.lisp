(in-package :cl-cc-runtime/test)

;;;; Tests for src/cluster.lisp — cluster membership registry + remote refs.
;;;;
;;;; These exercise the global membership hash table, so every test re-inits the
;;;; cluster via rt-cluster-init to avoid cross-test leakage. Struct accessors on
;;;; rt-cluster-node / rt-remote-actor-ref are unexported, hence the
;;;; cl-cc/runtime:: qualifications.
(it-sequential
  "rt-cluster-init installs the local node as :up and queryable by id."
  (expect (rt-cluster-init :id "self" :host "10.0.0.1" :port 7000) :to-be-truthy)
  (expect (rt-cluster-query-node-status "self") :to-be :up)
  (let ((local cl-cc/runtime::*rt-cluster-local*))
    (expect (cl-cc/runtime::rt-cluster-node-id local) :to-equal "self")
    (expect (cl-cc/runtime::rt-cluster-node-host local) :to-equal "10.0.0.1")
    (expect (cl-cc/runtime::rt-cluster-node-port local) :to-equal 7000)))

(it-sequential
  "Re-initializing drops nodes from a prior cluster generation."
  (rt-cluster-init :id "n1")
  (rt-cluster-join "n2" "127.0.0.1" 1)
  (expect (rt-cluster-query-node-status "n2") :to-be :up)
  (rt-cluster-init :id "fresh")
  (expect (rt-cluster-query-node-status "n2") :to-be-null)
  (expect (rt-cluster-query-node-status "n1") :to-be-null))

(it-sequential
  "A joined node is stored with :up status and its address."
  (rt-cluster-init :id "n1")
  (rt-cluster-join "n2" "192.168.1.5" 9999)
  (expect (rt-cluster-query-node-status "n2") :to-be :up)
  (let ((n (gethash "n2" cl-cc/runtime::*rt-cluster-nodes*)))
    (expect (cl-cc/runtime::rt-cluster-node-host n) :to-equal "192.168.1.5")
    (expect (cl-cc/runtime::rt-cluster-node-port n) :to-equal 9999)))

(it-sequential
  "Leaving removes a node so its status becomes unknown (NIL)."
  (rt-cluster-init :id "n1")
  (rt-cluster-join "n2" "127.0.0.1" 1)
  (rt-cluster-leave "n2")
  (expect (rt-cluster-query-node-status "n2") :to-be-null))

(it-sequential
  "Querying a node that never joined returns NIL."
  (rt-cluster-init :id "n1")
  (expect (rt-cluster-query-node-status "ghost") :to-be-null))

(it-sequential
  "The portable remote-send stub returns NIL without error."
  (expect
    (rt-remote-send (rt-make-remote-ref "n2" "actor-7") '(:ping))
    :to-be-null))

(it-sequential
  "A remote actor ref preserves its node and actor identifiers."
  (let ((ref (rt-make-remote-ref "node-9" "actor-3")))
    (expect (cl-cc/runtime::rt-remote-actor-ref-node-id ref) :to-equal "node-9")
    (expect (cl-cc/runtime::rt-remote-actor-ref-actor-id ref) :to-equal "actor-3")))
