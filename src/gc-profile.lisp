;;;; packages/runtime/src/gc-profile.lisp — GC allocation profiling and heap diagnostics

(in-package :cl-cc/runtime)

(defparameter *gc-profile-enabled* nil
  "When true, sample allocation sites every *gc-profile-interval* bytes.")

(defparameter *gc-profile-interval* (* 64 1024)
  "Allocation sampling interval in bytes.")

(defparameter *gc-profile-bytes-since-sample* 0)

(defparameter *gc-profile-samples* (make-hash-table :test #'equal))

(defparameter *gc-profile-current-function* :unknown)

(defun rt-gc-classify-hotness (heap addr)
  "Classify object ADDR in HEAP as :HOT, :WARM, or :COLD.

:HOT means the object header address has been observed by the heap access bitmap
during the current minor-GC epoch.  :WARM means the object was promoted to old
space in the previous minor collection window.  :COLD means an old-space object
has neither signal.  Young objects without an access bit are treated as :WARM."
  (check-type heap rt-heap)
  (check-type addr integer)
  (let ((access-cycle (and (rt-heap-access-bits heap)
                           (gethash addr (rt-heap-access-bits heap))))
        (promotion-cycle (and (rt-heap-recent-promotions heap)
                              (gethash addr (rt-heap-recent-promotions heap))))
        (minor-cycle (rt-heap-minor-gc-count heap)))
    (cond
      ((and access-cycle (or (= access-cycle minor-cycle)
                             (= access-cycle (max 0 (1- minor-cycle))))) :hot)
      ((and promotion-cycle (<= (- minor-cycle promotion-cycle) 1)) :warm)
      ((rt-old-addr-p heap addr) :cold)
      (t :warm))))

(defun %rt-gc-age-distribution-plist (heap)
  "Return RT-HEAP-AGE-HIST as (:AGE-0-COUNT N ... :AGE-15-COUNT N)."
  (loop for age from 0 below 16
        append (list (intern (format nil "AGE-~D-COUNT" age) :keyword)
                     (svref (rt-heap-age-hist heap) age))))

(defun %rt-gc-profile-stack-label ()
  *gc-profile-current-function*)

(defun rt-gc-profile-sample (bytes)
  "Record allocation profiling samples for BYTES newly allocated bytes."
  (when *gc-profile-enabled*
    (incf *gc-profile-bytes-since-sample* bytes)
    (loop while (>= *gc-profile-bytes-since-sample* *gc-profile-interval*) do
      (decf *gc-profile-bytes-since-sample* *gc-profile-interval*)
      (incf (gethash (%rt-gc-profile-stack-label) *gc-profile-samples* 0)))))

(defun rt-gc-profile-report ()
  "Return a plist containing sampled allocation hot spots."
  (let (hotspots)
    (maphash (lambda (site count)
               (push (list :function site :count count) hotspots))
             *gc-profile-samples*)
    (list :enabled-p *gc-profile-enabled*
          :interval-bytes *gc-profile-interval*
          :bytes-since-sample *gc-profile-bytes-since-sample*
          :hot-spots (sort hotspots #'> :key (lambda (entry) (getf entry :count))))))

(defun %rt-gc-object-type-name (tag)
  (case tag
    (0 :fixnum) (1 :cons) (2 :symbol) (3 :closure)
    (4 :character) (5 :array) (6 :string) (7 :other)
    (otherwise :unknown)))

(defun %rt-gc-walk-heap-objects (heap visitor)
  (labels ((walk-range (start end)
             (loop with addr = start
                   while (< addr end) do
                     (let ((h (rt-heap-object-header heap addr)))
                       (cond
                         ((header-forwarding-p h) (incf addr 1))
                         ((and (integerp h) (> (rt-header-size h) 0))
                          (let ((size (rt-header-size h)))
                            (funcall visitor addr h (rt-header-type-tag h) size)
                            (incf addr size)))
                         (t (return)))))))
    (walk-range (rt-heap-young-from-base heap) (rt-heap-young-free heap))
    (walk-range (rt-heap-old-base heap) (rt-heap-old-free heap))
    (walk-range (rt-heap-large-obj-base heap) (rt-heap-large-obj-free heap))))

(defun rt-gc-heap-snapshot (heap)
  "Return a plist snapshot of allocated heap objects with type, size, address, and edges."
  (let ((objects nil)
        (total-bytes 0))
    (%rt-gc-walk-heap-objects
     heap
     (lambda (addr header tag size)
       (declare (ignore header))
       (incf total-bytes (* size 8))
       (push (list :address addr
                   :type (%rt-gc-object-type-name tag)
                   :type-tag tag
                   :size-words size
                   :size-bytes (* size 8)
                   :references
                    (loop for offset in (rt-object-pointer-slots heap addr)
                          for value = (rt-heap-ref heap (+ addr offset))
                          for target = (%rt-gc-pointer-address heap value)
                          when target
                            collect (list :slot offset :address target)))
             objects)))
    (list :object-count (length objects)
          :total-bytes total-bytes
            :objects (nreverse objects))))

(defconstant +rt-heap-image-version+ 1
  "Portable heap-image format version used by RT-GC-SAVE-HEAP-IMAGE.")

(defun %rt-gc-hash-table-alist (table)
  (let (result)
    (when table
      (maphash (lambda (key value) (push (cons key value) result)) table))
    (nreverse result)))

(defun %rt-gc-alist-hash-table (alist &key (test #'eql))
  (let ((table (make-hash-table :test test)))
    (dolist (entry alist table)
      (setf (gethash (car entry) table) (cdr entry)))))

(defun %rt-gc-snapshot-addresses (snapshot)
  (mapcar (lambda (object) (getf object :address))
          (getf snapshot :objects)))

(defun rt-gc-heap-census (heap)
  "Return a plist of object counts and byte totals grouped by runtime type."
  (let ((cons-count 0) (cons-bytes 0)
        (symbol-count 0) (symbol-bytes 0)
        (closure-count 0) (closure-bytes 0)
        (array-count 0) (array-bytes 0)
        (string-count 0) (string-bytes 0)
        (other-count 0) (other-bytes 0)
        (object-count 0)
        (total-bytes 0))
    (%rt-gc-walk-heap-objects
     heap
     (lambda (addr header tag size)
        (declare (ignore addr header))
        (let ((bytes (* size 8)))
          (incf object-count)
          (incf total-bytes bytes)
          (case (%rt-gc-object-type-name tag)
            (:cons (incf cons-count) (incf cons-bytes bytes))
            (:symbol (incf symbol-count) (incf symbol-bytes bytes))
            (:closure (incf closure-count) (incf closure-bytes bytes))
            (:array (incf array-count) (incf array-bytes bytes))
            (:string (incf string-count) (incf string-bytes bytes))
            (otherwise (incf other-count) (incf other-bytes bytes))))))
    (list :cons-count cons-count :cons-bytes cons-bytes
          :symbol-count symbol-count :symbol-bytes symbol-bytes
          :closure-count closure-count :closure-bytes closure-bytes
          :array-count array-count :array-bytes array-bytes
           :string-count string-count :string-bytes string-bytes
           :other-count other-count :other-bytes other-bytes
           :total-objects object-count :total-bytes total-bytes)))

(defun %rt-gc-pointer-value-matches-p (heap value target)
  (let ((addr (%rt-gc-pointer-address heap value)))
    (eql addr target)))

(defun %rt-gc-heap-reference-count (heap target)
  "Count heap pointer slots that refer to TARGET."
  (let ((count 0))
    (%rt-gc-walk-heap-objects
     heap
     (lambda (addr header tag size)
       (declare (ignore header tag size))
       (dolist (offset (rt-object-pointer-slots heap addr))
         (when (%rt-gc-pointer-value-matches-p heap (rt-heap-ref heap (+ addr offset)) target)
           (incf count)))))
    count))

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
      (let (evict-keys)
        (maphash (lambda (key entry)
                   (when (or (eql (rt-code-cache-entry-class-key entry) class-key)
                             (eql (rt-code-cache-entry-class-key entry) class-addr))
                     (push key evict-keys)))
                 (rt-code-cache-entries *rt-code-cache*))
        (dolist (key evict-keys)
          (rt-code-cache-evict key)))
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

(defun rt-gc-heap-dump-dot (heap &optional stream)
  "Return or write a DOT-format object graph for HEAP."
  (let ((snapshot (rt-gc-heap-snapshot heap)))
    (flet ((emit (out)
             (format out "digraph cl_cc_heap {~%")
             (format out "  rankdir=LR;~%  node [shape=record,fontname=\"monospace\"];~%")
             (dolist (object (getf snapshot :objects))
               (format out "  obj~D [label=\"~D | ~A | ~D words\"];~%"
                       (getf object :address)
                       (getf object :address)
                       (getf object :type)
                       (getf object :size-words)))
             (dolist (object (getf snapshot :objects))
               (dolist (edge (getf object :references))
                 (format out "  obj~D -> obj~D [label=\"slot ~D\"];~%"
                         (getf object :address)
                         (getf edge :address)
                         (getf edge :slot))))
             (format out "}~%")))
      (if stream
          (emit stream)
          (with-output-to-string (out) (emit out))))))
