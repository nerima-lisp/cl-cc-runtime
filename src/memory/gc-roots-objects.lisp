;;;; gc-roots-objects.lisp — Pointer/root classification predicates and the
;;;; root registry (rt-gc-add-root, rt-gc-add-root-typed, rt-gc-remove-root).
;;;; Stack/binding scanning moved to gc-stackmaps.lisp and gc-binding-scan.lisp;
;;;; allocation moved to gc-alloc.lisp; rt-gc-verify-heap moved to
;;;; gc-heap-verify.lisp.
(in-package :cl-cc/runtime)

(defun %rt-gc-valid-header-p (header)
  (and (integerp header)
       (> (rt-header-size header) 0)
       (<= 0 (rt-header-type-tag header) 7)))

(defun %rt-gc-object-start-p (heap addr)
  "Return true when ADDR appears to designate a live heap object header."
  (and (integerp addr)
       (rt-heap-addr-p heap addr)
       (let ((header (rt-heap-object-header heap addr)))
         (or (header-forwarding-p header)
             (%rt-gc-valid-header-p header)))))

;;; FR-336: GC-NaN-Boxing Integration — uses val-pointer-p/decode-pointer for precise pointer
;;; identification during GC scanning
(defun %rt-gc-pointer-address (heap value)
  "Return the heap address encoded by VALUE, or NIL when VALUE is not a pointer.

NaN-boxed pointer values are recognized with VAL-POINTER-P and decoded with
DECODE-POINTER.  Runtime heap words that already contain object-start addresses
are accepted as canonical internal addresses."
  (cond
    ((and (typep value '(unsigned-byte 64)) (val-pointer-p value))
     (let ((addr (decode-pointer value)))
       (when (%rt-gc-object-start-p heap addr)
         addr)))
    ((%rt-gc-object-start-p heap value)
     value)
    (t nil)))

(defun %rt-gc-value-address-for-predicate (value predicate)
  "Return VALUE's decoded address when PREDICATE accepts it.

This is used during minor GC after from/to-space flipping, where the evacuation
source is no longer considered a live heap range by RT-HEAP-ADDR-P."
  (cond
    ((and (typep value '(unsigned-byte 64)) (val-pointer-p value))
     (let ((addr (decode-pointer value)))
       (when (funcall predicate addr) addr)))
    ((and (integerp value) (funcall predicate value))
     value)
    (t nil)))

(defun %rt-gc-rebox-pointer-like (old-value new-addr)
  "Preserve OLD-VALUE's pointer representation while replacing its address."
  (if (and (integerp old-value) (val-pointer-p old-value))
      (encode-pointer new-addr (pointer-tag old-value))
      new-addr))

(defun %rt-gc-root-type (heap root-cell)
  (or (cdr (assoc root-cell (gethash heap *rt-gc-root-types*) :test #'eq))
      :any))

(defun %rt-gc-root-pointer-address (heap root-cell)
  "Return ROOT-CELL's heap address according to its precise root metadata."
  (let ((value (cdr root-cell)))
    (case (%rt-gc-root-type heap root-cell)
      ((:pointer :any) (%rt-gc-pointer-address heap value))
      ((:fixnum :double :char) nil)
      (otherwise nil))))

;;; ------------------------------------------------------------
;;; Section 2: Root Registration
;;; ------------------------------------------------------------

(defun rt-gc-add-root (heap root-cell)
  "Register ROOT-CELL as a GC root.
   ROOT-CELL must be a cons whose cdr holds the heap address to keep live.
   The GC updates (cdr root-cell) in place when the object is moved."
  (rt-gc-add-root-typed heap root-cell :any))

(defun rt-gc-add-root-typed (heap root-cell type)
  "Register ROOT-CELL as a GC root with precise TYPE metadata.

  TYPE is one of :POINTER, :FIXNUM, :DOUBLE, :CHAR, or :ANY.  :ANY accepts either
  a boxed pointer value or a canonical internal heap address; typed non-pointer
  roots are skipped entirely by the collectors."
  (check-type root-cell cons)
  (unless (member type '(:pointer :fixnum :double :char :any) :test #'eq)
    (error "cl-cc/runtime: invalid GC root type ~S" type))
  (pushnew root-cell (rt-heap-roots heap) :test #'eq)
  (let ((alist (gethash heap *rt-gc-root-types*)))
    (setf (gethash heap *rt-gc-root-types*)
          (acons root-cell type (delete root-cell alist :key #'car :test #'eq))))
  root-cell)

(defun rt-gc-remove-root (heap root-cell)
  "Unregister ROOT-CELL from the GC root set."
  (setf (rt-heap-roots heap)
        (delete root-cell (rt-heap-roots heap) :test #'eq))
  (let ((alist (gethash heap *rt-gc-root-types*)))
    (setf (gethash heap *rt-gc-root-types*)
          (delete root-cell alist :key #'car :test #'eq)))
  root-cell)

;;; ------------------------------------------------------------
;;; Section 3: Minor GC — Cheney Copying
;;; ------------------------------------------------------------
