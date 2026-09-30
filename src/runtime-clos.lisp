;;;; runtime-clos — CL-CC Runtime: CLOS class/instance descriptors
;;;
;;; Contains: *rt-class-registry*, C3 linearization, rt-defclass,
;;; rt-make-instance, rt-slot-*, rt-class-*. Generic-function and method
;;; dispatch live in runtime-clos-dispatch.lisp.
;;;
;;; Depends on runtime.lisp. Load order: after runtime-misc.lisp.

(in-package :cl-cc/runtime)

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

(defun %rt-class-descriptor (class)
  "Resolve CLASS to a runtime class descriptor when one is registered."
  (cond
    ((hash-table-p class) class)
    ((gethash class *rt-class-registry*))
    (t nil)))

(defun %rt-effective-slots (class)
  "Return the inherited and direct slots of runtime CLASS, in class order."
  (let ((descriptor (%rt-class-descriptor class))
        (slots nil))
    (dolist (class-name (reverse (or (and descriptor (gethash :__cpl__ descriptor))
                                    (list class))))
      (let ((class-ht (%rt-class-descriptor class-name)))
        (dolist (slot (and class-ht (gethash :__slots__ class-ht)))
          (pushnew slot slots :test #'eq))))
    (nreverse slots)))

(defun %rt-runtime-instance-p (object)
  (and (hash-table-p object)
       (hash-table-p (gethash :__class__ object))))

(defun %rt-slot-key (slot-name)
  (unless (symbolp slot-name)
    (error "Runtime slot name must be a symbol, got ~S" slot-name))
  slot-name)

(defun %rt-set-initargs (object initargs)
  "Apply alternating keyword/value INITARGS to runtime OBJECT."
  (unless (evenp (length initargs))
    (error "Odd number of initialization arguments: ~S" initargs))
  (loop for (name value) on initargs by #'cddr
        for slot-name = (find-if (lambda (slot)
                                   (string-equal (symbol-name slot)
                                                 (symbol-name name)))
                                 (%rt-effective-slots (gethash :__class__ object)))
        do (unless (or (keywordp name) (symbolp name))
             (error "Initialization argument name must be a symbol: ~S" name))
           (when (and (keywordp name) (eq name :allow-other-keys))
             (return))
           (if slot-name
               (setf (gethash slot-name object) value
                     (gethash slot-name (gethash :__bound-slots__ object)) t)
               (error "Unknown runtime initialization slot ~S" name)))
  object)

(defun rt-make-instance (class &rest initargs)
  (if (%rt-class-descriptor class)
      (let ((object (make-hash-table :test #'eq)))
        (setf (gethash :__class__ object) (%rt-class-descriptor class)
              (gethash :__bound-slots__ object) (make-hash-table :test #'eq))
        (%rt-set-initargs object initargs))
      (apply #'make-instance class initargs)))

(defun rt-make-instance-0 (class)
  (rt-make-instance class))

(defun rt-slot-value (obj slot-name)
  (if (%rt-runtime-instance-p obj)
      (if (rt-slot-boundp obj slot-name)
          (gethash (%rt-slot-key slot-name) obj)
          (error "The runtime slot ~S is unbound" slot-name))
      (slot-value obj slot-name)))

(defun rt-slot-set (obj slot-name val)
  (if (%rt-runtime-instance-p obj)
      (progn
        (unless (rt-slot-exists-p obj slot-name)
          (error "The runtime slot ~S does not exist" slot-name))
        (let ((bound-slots (or (gethash :__bound-slots__ obj)
                               (setf (gethash :__bound-slots__ obj)
                                     (make-hash-table :test #'eq)))))
          (setf (gethash (%rt-slot-key slot-name) obj) val
                (gethash (%rt-slot-key slot-name) bound-slots) t))
        val)
      (setf (slot-value obj slot-name) val)))

(defun rt-slot-boundp (obj slot-name)
  (if (%rt-runtime-instance-p obj)
      (if (gethash (%rt-slot-key slot-name) (gethash :__bound-slots__ obj)) 1 0)
      (if (slot-boundp obj slot-name) 1 0)))

(defun rt-slot-makunbound (obj slot-name)
  (if (%rt-runtime-instance-p obj)
      (progn
        (remhash (%rt-slot-key slot-name) obj)
        (remhash (%rt-slot-key slot-name) (gethash :__bound-slots__ obj))
        obj)
      (slot-makunbound obj slot-name)))

(defun rt-slot-exists-p (obj slot-name)
  (if (%rt-runtime-instance-p obj)
      (if (member (%rt-slot-key slot-name)
                  (%rt-effective-slots (gethash :__class__ obj)) :test #'eq)
          1 0)
      (if (slot-exists-p obj slot-name) 1 0)))

(defun rt-reinitialize-instance (object &rest initargs)
  "Reinitialize a runtime instance, or delegate to host CLOS."
  (if (%rt-runtime-instance-p object)
      (%rt-set-initargs object initargs)
      (apply #'reinitialize-instance object initargs)))

(defun rt-change-class (object new-class &rest initargs)
  "Change the class of OBJECT while preserving slots shared by both classes."
  (if (%rt-runtime-instance-p object)
      (let* ((old-class (gethash :__class__ object))
             (old-bound (gethash :__bound-slots__ object))
             (new-descriptor (%rt-class-descriptor new-class)))
        (unless new-descriptor
          (error "Unknown runtime class ~S" new-class))
        (let ((old-values (make-hash-table :test #'eq)))
          (dolist (slot (%rt-effective-slots old-class))
            (when (gethash slot old-bound)
              (setf (gethash slot old-values) (gethash slot object))))
          (setf (gethash :__class__ object) new-descriptor
                (gethash :__bound-slots__ object) (make-hash-table :test #'eq))
          (dolist (slot (%rt-effective-slots new-descriptor))
            (multiple-value-bind (value presentp) (gethash slot old-values)
              (when presentp
                (setf (gethash slot object) value
                      (gethash slot (gethash :__bound-slots__ object)) t))))
          (%rt-set-initargs object initargs)
          object))
      (apply #'change-class object new-class initargs)))

(defun rt-class-name (class)
  (if (hash-table-p class)
      (gethash :__name__ class)
      (class-name class)))

(defun rt-class-of (obj)
  (if (%rt-runtime-instance-p obj)
      (gethash :__class__ obj)
      (class-of obj)))

(defun rt-find-class (name)
  (or (gethash name *rt-class-registry*)
      (find-class name nil)))
