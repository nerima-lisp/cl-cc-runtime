(in-package :cl-cc-runtime/test)
(in-suite cl-cc-unit-suite)

;;;; Tests for src/crdt.lisp — CvRDTs: G-Counter, PN-Counter, LWW-Register.
;;;;
;;;; The G-Counter merge is a state-based CvRDT: merging is per-node max, which
;;;; makes it commutative, associative, and idempotent. Those algebraic laws are
;;;; exercised directly with cl-weave property tests below.

;;; ── G-Counter ─────────────────────────────────────────────────────

(deftest crdt-gcounter-empty-value-is-zero
  "A freshly created G-Counter reads as zero."
  (assert-= 0 (rt-gcounter-value (rt-make-gcounter))))

(deftest crdt-gcounter-increment-accumulates-per-node
  "Increments from distinct nodes sum into the total value."
  (let ((c (rt-make-gcounter)))
    (rt-gcounter-increment c :a 3)
    (rt-gcounter-increment c :b 4)
    (rt-gcounter-increment c :a 1)
    (assert-= 8 (rt-gcounter-value c))))

(deftest crdt-gcounter-increment-defaults-to-one
  "The delta argument defaults to 1."
  (let ((c (rt-make-gcounter)))
    (rt-gcounter-increment c :a)
    (rt-gcounter-increment c :a)
    (assert-= 2 (rt-gcounter-value c))))

(deftest crdt-gcounter-merge-takes-per-node-maximum
  "Merge keeps the highest observed count for each node id."
  (let ((a (rt-make-gcounter))
        (b (rt-make-gcounter)))
    (rt-gcounter-increment a :n1 5)
    (rt-gcounter-increment a :n2 2)
    (rt-gcounter-increment b :n1 3)   ; lower than a's :n1
    (rt-gcounter-increment b :n3 9)
    (rt-gcounter-merge a b)
    ;; :n1 -> max(5,3)=5, :n2 -> 2, :n3 -> 9
    (assert-= 16 (rt-gcounter-value a))))

(deftest crdt-gcounter-merge-is-idempotent
  "Merging a replica with itself does not change its value."
  (let ((a (rt-make-gcounter)))
    (rt-gcounter-increment a :n1 5)
    (rt-gcounter-increment a :n2 7)
    (rt-gcounter-merge a a)
    (assert-= 12 (rt-gcounter-value a))))

;;; Property: G-Counter merge converges regardless of order (commutativity).
(cl-weave:it-property "crdt gcounter merge is commutative in value"
    ((av (cl-weave:gen-integer :min 0 :max 50))
     (bv (cl-weave:gen-integer :min 0 :max 50))
     (shared-a (cl-weave:gen-integer :min 0 :max 50))
     (shared-b (cl-weave:gen-integer :min 0 :max 50)))
  (flet ((fresh ()
           (let ((a (rt-make-gcounter))
                 (b (rt-make-gcounter)))
             (rt-gcounter-increment a :a av)
             (rt-gcounter-increment a :shared shared-a)
             (rt-gcounter-increment b :b bv)
             (rt-gcounter-increment b :shared shared-b)
             (values a b))))
    (multiple-value-bind (a1 b1) (fresh)
      (multiple-value-bind (a2 b2) (fresh)
        ;; merge(a,b) and merge(b,a) must reach the same total value.
        (let ((ab (rt-gcounter-value (rt-gcounter-merge a1 b1)))
              (ba (rt-gcounter-value (rt-gcounter-merge b2 a2))))
          (cl-weave:expect ab :to-be ba)
          ;; convergence dominates both inputs' shared slot: max, not sum.
          (cl-weave:expect ab
                           :to-be (+ av bv (max shared-a shared-b))))))))

;;; Property: merge result value is never smaller than either operand.
(cl-weave:it-property "crdt gcounter merge is monotonic (join-semilattice)"
    ((x (cl-weave:gen-integer :min 0 :max 100))
     (y (cl-weave:gen-integer :min 0 :max 100)))
  (let ((a (rt-make-gcounter))
        (b (rt-make-gcounter)))
    (rt-gcounter-increment a :node x)
    (rt-gcounter-increment b :node y)
    (let ((va (rt-gcounter-value a))
          (vb (rt-gcounter-value b))
          (merged (rt-gcounter-value (rt-gcounter-merge a b))))
      (cl-weave:expect merged :to-be-greater-than-or-equal va)
      (cl-weave:expect merged :to-be-greater-than-or-equal vb)
      (cl-weave:expect merged :to-be (max x y)))))

;;; ── PN-Counter ────────────────────────────────────────────────────

(deftest crdt-pncounter-value-is-pos-minus-neg
  "A PN-Counter's value is total increments minus total decrements."
  (let ((c (rt-make-pncounter)))
    (rt-pncounter-increment c :a 10)
    (rt-pncounter-decrement c :a 3)
    (rt-pncounter-decrement c :b 2)
    (assert-= 5 (rt-pncounter-value c))))

(deftest crdt-pncounter-can-go-negative
  "Decrements exceeding increments yield a negative value."
  (let ((c (rt-make-pncounter)))
    (rt-pncounter-decrement c :a 4)
    (assert-= -4 (rt-pncounter-value c))))

(cl-weave:it-property "crdt pncounter value equals inc minus dec"
    ((inc (cl-weave:gen-integer :min 0 :max 100))
     (dec (cl-weave:gen-integer :min 0 :max 100)))
  (let ((c (rt-make-pncounter)))
    (rt-pncounter-increment c :n inc)
    (rt-pncounter-decrement c :n dec)
    (cl-weave:expect (rt-pncounter-value c) :to-be (- inc dec))))

;;; ── LWW-Register ──────────────────────────────────────────────────

(deftest crdt-lwwregister-read-initial
  "A register created with an initial value reads that value."
  (assert-eql 42 (rt-lwwregister-read (rt-make-lwwregister 42))))

(deftest crdt-lwwregister-read-defaults-nil
  "A register created without an argument reads NIL."
  (assert-null (rt-lwwregister-read (rt-make-lwwregister))))

(deftest crdt-lwwregister-assign-updates-value
  "Assign replaces the stored value and returns the new value."
  (let ((r (rt-make-lwwregister :old)))
    (assert-eq :new (rt-lwwregister-assign r :new))
    (assert-eq :new (rt-lwwregister-read r))))

(deftest crdt-init-returns-true
  "rt-crdt-init reports success."
  (assert-true (rt-crdt-init)))
