(in-package :cl-cc-runtime/test)

;;;; Tests for src/crdt.lisp — CvRDTs: G-Counter, PN-Counter, LWW-Register.
;;;;
;;;; The G-Counter merge is a state-based CvRDT: merging is per-node max, which
;;;; makes it commutative, associative, and idempotent. Those algebraic laws are
;;;; exercised directly with cl-weave property tests below.
;;; ── G-Counter ─────────────────────────────────────────────────────
(it-sequential
  "A freshly created G-Counter reads as zero."
  (expect (rt-gcounter-value (rt-make-gcounter)) :to-equal 0))

(it-sequential
  "Increments from distinct nodes sum into the total value."
  (let ((c (rt-make-gcounter)))
    (rt-gcounter-increment c :a 3)
    (rt-gcounter-increment c :b 4)
    (rt-gcounter-increment c :a 1)
    (expect (rt-gcounter-value c) :to-equal 8)))

(it-sequential
  "The delta argument defaults to 1."
  (let ((c (rt-make-gcounter)))
    (rt-gcounter-increment c :a)
    (rt-gcounter-increment c :a)
    (expect (rt-gcounter-value c) :to-equal 2)))

(it-sequential "Merge keeps the highest observed count for each node id." (let ((a (rt-make-gcounter))
        (b (rt-make-gcounter)))
    (rt-gcounter-increment a :n1 5)
    (rt-gcounter-increment a :n2 2)
    (rt-gcounter-increment b :n1 3)   ; lower than a's :n1
    (rt-gcounter-increment b :n3 9)
    (rt-gcounter-merge a b)
    ;; :n1 -> max(5,3)=5, :n2 -> 2, :n3 -> 9
    (expect (rt-gcounter-value a) :to-equal 16)))

(it-sequential
  "Merging a replica with itself does not change its value."
  (let ((a (rt-make-gcounter)))
    (rt-gcounter-increment a :n1 5)
    (rt-gcounter-increment a :n2 7)
    (rt-gcounter-merge a a)
    (expect (rt-gcounter-value a) :to-equal 12)))

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
(cl-weave:it-property
  "crdt gcounter merge is monotonic (join-semilattice)"
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
(it-sequential
  "A PN-Counter's value is total increments minus total decrements."
  (let ((c (rt-make-pncounter)))
    (rt-pncounter-increment c :a 10)
    (rt-pncounter-decrement c :a 3)
    (rt-pncounter-decrement c :b 2)
    (expect (rt-pncounter-value c) :to-equal 5)))

(it-sequential
  "Decrements exceeding increments yield a negative value."
  (let ((c (rt-make-pncounter)))
    (rt-pncounter-decrement c :a 4)
    (expect (rt-pncounter-value c) :to-equal -4)))

(cl-weave:it-property
  "crdt pncounter value equals inc minus dec"
  ((inc (cl-weave:gen-integer :min 0 :max 100))
    (dec (cl-weave:gen-integer :min 0 :max 100)))
  (let ((c (rt-make-pncounter)))
    (rt-pncounter-increment c :n inc)
    (rt-pncounter-decrement c :n dec)
    (cl-weave:expect (rt-pncounter-value c) :to-be (- inc dec))))

;;; ── LWW-Register ──────────────────────────────────────────────────
(it-sequential
  "A register created with an initial value reads that value."
  (expect (rt-lwwregister-read (rt-make-lwwregister 42)) :to-be 42))

(it-sequential
  "A register created without an argument reads NIL."
  (expect (rt-lwwregister-read (rt-make-lwwregister)) :to-be-null))

(it-sequential
  "Assign replaces the stored value and returns the new value."
  (let ((r (rt-make-lwwregister :old)))
    (expect (rt-lwwregister-assign r :new) :to-be :new)
    (expect (rt-lwwregister-read r) :to-be :new)))

(it-sequential
  "rt-crdt-init reports success."
  (expect (rt-crdt-init) :to-be-truthy))
