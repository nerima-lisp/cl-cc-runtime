;;;; gc-pinning.lisp — Object pinning for FFI (rt-pin-object, rt-unpin-object,
;;;; with-pinned-objects), split out of gc-policy.lisp
(in-package :cl-cc/runtime)

(defun %rt-pinned-table (heap &key create)
  (or (gethash heap *rt-pinned-objects*)
      (when create
        (setf (gethash heap *rt-pinned-objects*)
              (make-hash-table :test #'eql)))))

(defun %rt-normalize-pin-address (addr)
  (if (and (integerp addr) (val-pointer-p addr))
      (decode-pointer addr)
      addr))

(defun rt-object-pinned-p (heap addr)
  "Return true when ADDR is pinned in HEAP.

Pinned objects are relocation barriers for compaction; compaction must preserve
their addresses and avoid sliding other objects through them."
  (let ((table (%rt-pinned-table heap)))
    (and table (gethash (%rt-normalize-pin-address addr) table))))

;;; FR-212: Object Pinning — prevents GC from relocating pinned objects; essential for FFI safety
(defun rt-pin-object (heap addr)
  "Pin object address ADDR in HEAP and return the normalized address.

Pinning prevents old-space compaction from moving the object.  Young pinned
objects encountered by minor GC are forced into the promotion path so roots do
not retain addresses in the inactive semi-space after a flip."
  (check-type heap rt-heap)
  (let ((normalized (%rt-normalize-pin-address addr)))
    (unless (integerp normalized)
      (error "cl-cc/runtime: cannot pin non-address value ~S" addr))
    (setf (gethash normalized (%rt-pinned-table heap :create t)) t)
    normalized))

(defun rt-unpin-object (heap addr)
  "Remove ADDR from HEAP's pin set and return the normalized address."
  (check-type heap rt-heap)
  (let ((normalized (%rt-normalize-pin-address addr))
        (table (%rt-pinned-table heap)))
    (when table
      (remhash normalized table))
    normalized))

;;; FR-212: Object Pinning — prevents GC from relocating pinned objects; essential for FFI safety
(defmacro with-pinned-objects (bindings &body body)
  "Evaluate BODY with objects pinned for its dynamic extent.

Each binding is either (VAR OBJ), using *RT-CURRENT-PINNING-HEAP*, or
(VAR HEAP OBJ), using an explicit heap expression.  VAR receives OBJ's value.
All pinned objects are unpinned by UNWIND-PROTECT.  Pinning documents a hard
relocation barrier: compaction must not move pinned objects."
  (let ((pins (gensym "PINS")))
    (labels ((parse-binding (binding)
               (destructuring-bind (var &rest rest) binding
                 (ecase (length rest)
                   (1 (values var '*rt-current-pinning-heap* (first rest)))
                   (2 (values var (first rest) (second rest)))))))
      (let ((lets nil)
            (pin-forms nil))
        (dolist (binding bindings)
          (multiple-value-bind (var heap-form obj-form) (parse-binding binding)
            (push `(,var ,obj-form) lets)
            (push `(let ((heap ,heap-form))
                     (unless heap
                       (error "cl-cc/runtime: WITH-PINNED-OBJECTS requires a heap for ~S" ',var))
                     (rt-pin-object heap ,var)
                     (push (cons heap ,var) ,pins))
                  pin-forms)))
        `(let ,(nreverse lets)
           (let ((,pins nil))
             (unwind-protect
                  (progn
                    ,@(nreverse pin-forms)
                    ,@body)
               (dolist (pin ,pins)
                 (rt-unpin-object (car pin) (cdr pin))))))))))
