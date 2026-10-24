;;;; runtime-clos — CL-CC Runtime: CLOS class/instance descriptors
;;;
;;; Contains: *rt-class-registry*, C3 linearization, rt-defclass,
;;; rt-make-instance, rt-slot-*, rt-class-*. Generic-function and method
;;; dispatch live in runtime-clos-dispatch.lisp.
;;;
;;; Depends on runtime.lisp. Load order: after runtime-misc.lisp.

(in-package :cl-cc/runtime/clos)

;;; ------------------------------------------------------------
;;; Class Registry
;;; ------------------------------------------------------------

(defvar *rt-class-registry* (make-hash-table :test #'eq)
  "Runtime class registry for native/self-hosted CLOS descriptors.")

(defvar *rt-generic-function-registry* (make-hash-table :test #'equal)
  "Runtime generic-function registry.

Keys are generic-function names (or the descriptor itself when unnamed). Values
are cons cells of (METHODS . DISPATCH-INFO).  METHODS is the registration-order
list of runtime method descriptors. DISPATCH-INFO stores derived dispatch data
used by RT-COMPUTE-APPLICABLE-METHODS and RT-CALL-GENERIC.")

(defvar *rt-method-registration-counter* 0
  "Monotonic counter preserving native-runtime method registration order.")

(defun %rt-cpl-walk (name seen)
  "Accumulate class precedence list starting from NAME with SEEN already visited."
  (if (member name seen :test #'eq)
      seen
      (let* ((class-ht (gethash name *rt-class-registry*))
             (supers (and class-ht (gethash :__superclasses__ class-ht))))
        (reduce (lambda (acc super) (%rt-cpl-walk super acc))
                supers
                :initial-value (append seen (list name))))))

(defun %rt-c3-merge (linearizations)
  "Merge LINEARIZATIONS using the same C3 rule as the VM CLOS dispatcher."
  (let ((result nil))
    (loop
      (setf linearizations (remove nil linearizations))
      (when (null linearizations)
        (return (nreverse result)))
      (let ((good-head nil))
        (dolist (lin linearizations)
          (let ((candidate (first lin)))
            (when (notany (lambda (other)
                            (member candidate (rest other) :test #'eq))
                          linearizations)
              (setf good-head candidate)
              (return))))
        (unless good-head
          (error "C3 linearization: inconsistent runtime class precedence for ~S"
                 linearizations))
        (push good-head result)
        (setf linearizations
              (mapcar (lambda (lin)
                        (if (eq (first lin) good-head) (rest lin) lin))
                      linearizations))))))

(defun %rt-cpl-linearize (name)
  "Compute C3 class precedence list for NAME from *RT-CLASS-REGISTRY*."
  (let ((class-ht (gethash name *rt-class-registry*)))
    (if (null class-ht)
        (list name)
        (let ((supers (gethash :__superclasses__ class-ht)))
          (if (null supers)
              (list name)
              (cons name
                    (%rt-c3-merge
                     (append (mapcar #'%rt-cpl-linearize supers)
                             (list (copy-list supers))))))))))

(defun %rt-compute-class-precedence-list (class-name)
  "Compute a C3 class precedence list from *rt-class-registry*."
  (%rt-cpl-linearize class-name))

(defun rt-defclass (name direct-supers slots)
  (let ((class-ht (or (gethash name *rt-class-registry*)
                      (make-hash-table :test #'eq))))
    (setf (gethash :__name__         class-ht) name
          (gethash :__superclasses__ class-ht) direct-supers
          (gethash :__slots__        class-ht) slots
          (gethash :__methods__      class-ht) (or (gethash :__methods__  class-ht)
                                                   (make-hash-table :test #'equal))
          (gethash :__eql-index__    class-ht) (or (gethash :__eql-index__ class-ht)
                                                   (make-hash-table :test #'equal))
          (gethash :__satiated__     class-ht) (or (gethash :__satiated__ class-ht) nil)
          (gethash '__ic-gen__       class-ht) (or (gethash '__ic-gen__ class-ht) 0)
          (gethash :__sealed__       class-ht) (or (gethash :__sealed__ class-ht) nil)
          (gethash name *rt-class-registry*)   class-ht
          (gethash :__cpl__          class-ht) (%rt-compute-class-precedence-list name))
    class-ht))

;;; ------------------------------------------------------------
;;; Instance Access
;;; ------------------------------------------------------------

(defun rt-make-instance (class &rest initargs)
  (apply #'make-instance class initargs))

(defun rt-make-instance-0 (class)
  (make-instance class))

(defun rt-slot-value (obj slot-name)
  (slot-value obj slot-name))

(defun rt-slot-set (obj slot-name val)
  (setf (slot-value obj slot-name) val))

(defun rt-slot-boundp (obj slot-name)
  (if (slot-boundp obj slot-name) 1 0))

(defun rt-slot-makunbound (obj slot-name)
  (slot-makunbound obj slot-name))

(defun rt-slot-exists-p (obj slot-name)
  (if (slot-exists-p obj slot-name) 1 0))

(defun rt-class-name (class)
  (if (hash-table-p class)
      (gethash :__name__ class)
      (class-name class)))

(defun rt-class-of (obj) (class-of obj))

(defun rt-find-class (name)
  (or (gethash name *rt-class-registry*)
      (find-class name nil)))

(in-package :cl-cc/runtime/clos)

(defun rt-next-method-p ()
  "Return true when a next method is available in the current runtime context."
  (let ((ctx (first *rt-method-context-stack*)))
    (and ctx (getf ctx :next-thunk) t)))

(defun rt-call-next-method (&rest args)
  "Invoke the next applicable native-runtime method.

When ARGS is empty, reuse the current generic-function arguments.  Otherwise use
ARGS as the replacement argument list, matching Common Lisp CALL-NEXT-METHOD
calling convention at the native runtime layer."
  (let* ((ctx (first *rt-method-context-stack*))
         (next-thunk (and ctx (getf ctx :next-thunk))))
    (unless next-thunk
      (error "call-next-method: no next method"))
    (funcall next-thunk (if args args (getf ctx :args)))))

(defvar *rt-method-context-stack* nil
  "Dynamic stack of native-runtime generic-function method contexts.

Each frame is a plist with at least :NEXT-THUNK and :ARGS.  RT-CALL-NEXT-METHOD
uses this stack to emulate the VM method-call stack for host-backed runtime
dispatch.")

(in-package :cl-cc/runtime/clos)

(defun %rt-gc-class-descriptor (class-addr)
  (cond
    ((hash-table-p class-addr) class-addr)
    ((symbolp class-addr) (gethash class-addr *rt-class-registry*))
    (t nil)))

(defun %rt-gc-class-registry-key (class-addr descriptor)
  (cond
    ((symbolp class-addr) class-addr)
    ((hash-table-p descriptor) (gethash :__name__ descriptor))
    (t nil)))

(defun %rt-gc-class-instance-count (heap class-addr descriptor)
  "Return best-effort live instance count for CLASS-ADDR/DESCRIPTOR."
  (cond
    ((and descriptor (gethash :__instance-count__ descriptor))
     (gethash :__instance-count__ descriptor))
    ((integerp class-addr)
     (%rt-gc-heap-reference-count heap class-addr))
    (t 0)))

(defun rt-gc-maybe-unload-class (heap class-addr)
  "Unload CLASS-ADDR from the runtime class registry when it has zero instances.

For heap-backed class descriptors CLASS-ADDR may be an address and the heap is
scanned for references.  For runtime descriptor hash tables or symbols, an
optional :__INSTANCE-COUNT__ registry field is honored; absent that, the class is
considered instance-free.  Associated JIT code-cache entries are evicted by class
key."
  (check-type heap rt-heap)
  (let* ((descriptor (%rt-gc-class-descriptor class-addr))
         (class-key (%rt-gc-class-registry-key class-addr descriptor))
         (instances (%rt-gc-class-instance-count heap class-addr descriptor)))
    (when (zerop instances)
      (when class-key
        (remhash class-key *rt-class-registry*))
      (rt-code-cache-evict-class class-key class-addr)
      (list :unloaded-p t :class class-key :instances instances))))

(defun rt-gc-run-unload-pass (heap)
  "Run the integrated FR-438 class/code unload pass after major sweep.

Only class descriptors explicitly marked with :__UNLOADABLE__ are considered by
the automatic pass, avoiding accidental removal of bootstrap/runtime classes.
Direct callers can still use RT-GC-MAYBE-UNLOAD-CLASS for a specific class."
  (let (unloaded candidates)
    (maphash (lambda (class-name descriptor)
               (when (and (hash-table-p descriptor)
                          (gethash :__unloadable__ descriptor))
                 (push class-name candidates)))
             *rt-class-registry*)
    (dolist (class-name candidates)
      (let ((result (rt-gc-maybe-unload-class heap class-name)))
        (when result (push result unloaded))))
    (nreverse unloaded)))

(eval-when (:load-toplevel :execute)
  (rt-gc-register-post-sweep-hook #'rt-gc-run-unload-pass))
