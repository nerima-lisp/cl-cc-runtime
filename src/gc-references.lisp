;;;; packages/runtime/src/gc-references.lisp — Reference strength runtime
;;;; support: soft/weak/phantom reference and hash-consing primitives. The
;;;; GC-time processing passes over them are in gc-weak-processing.lisp.

(in-package :cl-cc/runtime)

(defstruct (rt-soft-ref (:constructor %make-rt-soft-ref))
  referent
  (last-access-time 0 :type integer)
  queue)

(defstruct (rt-weak-ref (:constructor %make-rt-weak-ref))
  referent
  queue)

(defstruct (rt-phantom-ref (:constructor %make-rt-phantom-ref))
  referent
  (enqueued nil :type boolean)
  queue)

;;; FR-384: Reference Queue Processing — GC enqueues cleared refs; a dedicated
;;; thread processes the callbacks independently.
(defstruct (rt-reference-queue (:constructor make-rt-reference-queue))
  "Queue of references cleared by GC, drained by the reference-queue thread."
  (entries nil :type list))

(defvar *rt-reference-registry* nil)
(defvar *rt-default-reference-queue* (make-rt-reference-queue))

(defvar *rt-weak-hash-table-registry* nil
  "All runtime weak hash tables.  The collector uses this metadata to remove
entries whose weak key/value has died without treating the metadata itself as a
strong reference.")

(defstruct (rt-hash-cons-entry (:constructor %make-rt-hash-cons-entry))
  "Weak registration for hash-consed canonical objects."
  object
  weak-ref
  (refcount 0 :type integer))

(defvar *rt-hash-cons-registry* (make-hash-table :test #'eq)
  "Canonical hash-consed object -> RT-HASH-CONS-ENTRY weak metadata.")

(defun %rt-register-reference (ref)
  (pushnew ref *rt-reference-registry* :test #'eq)
  ref)

(defun rt-make-soft-ref (referent &optional (queue *rt-default-reference-queue*))
  (%rt-register-reference
   (%make-rt-soft-ref :referent referent
                      :last-access-time (get-internal-real-time)
                      :queue queue)))

(defun rt-make-weak-ref (referent &optional (queue *rt-default-reference-queue*))
  (%rt-register-reference (%make-rt-weak-ref :referent referent :queue queue)))

(defun rt-make-weak-pointer (referent &optional (queue *rt-default-reference-queue*))
  "Create a weak pointer to REFERENT.  The referent is not treated as a GC root."
  (rt-make-weak-ref referent queue))

(defun rt-weak-pointer-p (object)
  "Return true when OBJECT is a runtime weak pointer."
  (rt-weak-ref-p object))

(defun rt-weak-pointer-value (weak-pointer)
  "Return WEAK-POINTER's referent, or NIL after the GC clears it."
  (rt-ref-get weak-pointer))

(defun (setf rt-weak-pointer-value) (value weak-pointer)
  "Retarget WEAK-POINTER to VALUE without creating a strong GC root."
  (check-type weak-pointer rt-weak-ref)
  (setf (rt-weak-ref-referent weak-pointer) value))

(defun rt-register-hash-cons (cons-cell)
  "Register CONS-CELL as a hash-consed canonical object via a weak reference.

Hash-consed objects keep identity through the canonical entry.  The entry itself
does not strongly keep the cons alive: GC/reference processing may clear the weak
reference, and hash-cons entries whose REFCOUNT is zero are removed by
%RT-GC-SWEEP-HASH-CONSING during collection."
  (let ((entry (or (gethash cons-cell *rt-hash-cons-registry*)
                   (%make-rt-hash-cons-entry
                    :object cons-cell
                    :weak-ref (rt-make-weak-ref cons-cell)
                    :refcount 0))))
    (setf (gethash cons-cell *rt-hash-cons-registry*) entry)
    entry))

(defun %rt-gc-sweep-hash-consing ()
  "Remove hash-cons registry entries whose canonical object has refcount zero."
  (maphash (lambda (object entry)
             (when (or (zerop (rt-hash-cons-entry-refcount entry))
                       (rt-ref-clear-p (rt-hash-cons-entry-weak-ref entry)))
               (remhash object *rt-hash-cons-registry*)))
           *rt-hash-cons-registry*)
  *rt-hash-cons-registry*)

(defun rt-make-phantom-ref (referent &optional (queue *rt-default-reference-queue*))
  (%rt-register-reference (%make-rt-phantom-ref :referent referent :queue queue)))

(defun rt-ref-get (ref)
  (etypecase ref
    (rt-soft-ref
     (let ((referent (rt-soft-ref-referent ref)))
       (when referent
         (setf (rt-soft-ref-last-access-time ref) (get-internal-real-time)))
       referent))
    (rt-weak-ref (rt-weak-ref-referent ref))
    (rt-phantom-ref nil)))

(defun rt-ref-clear-p (ref)
  (etypecase ref
    (rt-soft-ref (null (rt-soft-ref-referent ref)))
    (rt-weak-ref (null (rt-weak-ref-referent ref)))
    (rt-phantom-ref (rt-phantom-ref-enqueued ref))))

(defun %rt-reference-queue-push (queue ref)
  (when queue
    (push ref (rt-reference-queue-entries queue)))
  ref)

(defun %rt-reference-clear (ref)
  (etypecase ref
    (rt-soft-ref
     (when (rt-soft-ref-referent ref)
       (setf (rt-soft-ref-referent ref) nil)
       (%rt-reference-queue-push (rt-soft-ref-queue ref) ref)))
    (rt-weak-ref
     (when (rt-weak-ref-referent ref)
       (setf (rt-weak-ref-referent ref) nil)
       (%rt-reference-queue-push (rt-weak-ref-queue ref) ref)))
    (rt-phantom-ref
     (unless (rt-phantom-ref-enqueued ref)
       (setf (rt-phantom-ref-referent ref) nil
             (rt-phantom-ref-enqueued ref) t)
        (%rt-reference-queue-push (rt-phantom-ref-queue ref) ref)))))

(defun %rt-gc-reference-value-address (heap value)
  "Return VALUE's heap address, or NIL for non-heap host values."
  (%rt-gc-pointer-address heap value))

(defun %rt-gc-reference-live-p (heap marked-set value)
  "True when VALUE is not managed by HEAP or its managed referent is live.

Host values are outside the cl-cc heap and are therefore not cleared by the
runtime GC.  Heap values are live when they are young/current large objects or
when their old-space header was marked by the major collector."
  (let ((addr (%rt-gc-reference-value-address heap value)))
    (or (null addr)
        (gethash addr marked-set))))

(defun %rt-gc-add-range-to-marked-set (heap marked-set start end predicate)
  "Add object starts in [START, END) satisfying PREDICATE to MARKED-SET."
  (loop with addr = start
        while (< addr end) do
          (let ((h (rt-heap-object-header heap addr)))
            (cond
              ((header-forwarding-p h) (incf addr 1))
              ((or (not (integerp h)) (zerop (rt-header-size h))) (return))
              (t
               (when (funcall predicate h)
                 (setf (gethash addr marked-set) t))
               (incf addr (rt-header-size h))))))
  marked-set)

(defun %rt-gc-build-marked-set (heap)
  "Build an address set from the completed major-GC mark state.

All allocated young objects are live for an old-generation collection.  Old
objects are live only when their mark bit is set; this function must run before
sweep clears those bits."
  (let ((marked-set (make-hash-table :test #'eql)))
    (%rt-gc-add-range-to-marked-set
     heap marked-set
     (rt-heap-young-from-base heap) (rt-heap-young-free heap)
     (lambda (h) (declare (ignore h)) t))
    (%rt-gc-add-range-to-marked-set
     heap marked-set
     (rt-heap-old-base heap) (rt-heap-old-free heap)
     #'header-marked-p)
    (%rt-gc-add-range-to-marked-set
     heap marked-set
     (rt-heap-large-obj-base heap) (rt-heap-large-obj-free heap)
     (lambda (h) (declare (ignore h)) t))
    marked-set))

(defun rt-reference-queue-process (queue callback)
  (check-type queue rt-reference-queue)
  (check-type callback function)
  (let ((entries (nreverse (rt-reference-queue-entries queue)))
        (count 0))
    (setf (rt-reference-queue-entries queue) nil)
    (dolist (ref entries count)
      (funcall callback ref)
      (incf count))))
