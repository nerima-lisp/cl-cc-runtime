;;;; runtime-weak-hash-table.lisp — rt-make-hash-table and weak-hash-table
;;;; support, split out of runtime-math-io.lisp
(in-package :cl-cc/runtime/values)

;;; ------------------------------------------------------------
;;; Hash Tables
;;; ------------------------------------------------------------
(defparameter +rt-hash-table-weakness-modes+
  '(nil :key :value :key-and-value :key-or-value)
  "Supported runtime hash-table weakness modes.")

(defstruct (rt-weak-hash-table (:constructor %make-rt-weak-hash-table))
  "Runtime hash-table wrapper that records the requested weakness mode."
  table
  weakness
  entries)

(defun %rt-valid-hash-weakness-p (weakness)
  (member weakness +rt-hash-table-weakness-modes+ :test #'eq))

(defun %rt-make-backing-hash-table (test size
                                         rehash-size
                                         rehash-threshold
                                         weakness)
  "Create a strong host hash table for RT hash-table wrappers.

Weakness is represented by RT-WEAK-HASH-TABLE metadata and GC cleanup rather
than by host weak tables, so the backing table is always strong."
  (declare (ignore weakness))
  (let ((args (list :test test)))
    (when size
      (setf args (append args (list :size size))))
    (when rehash-size
      (setf args (append args (list :rehash-size rehash-size))))
    (when rehash-threshold
      (setf args (append args (list :rehash-threshold rehash-threshold))))
    (apply #'cl:make-hash-table args)))

(defun %rt-hash-table-backing (ht)
  (etypecase ht
    (rt-weak-hash-table (rt-weak-hash-table-table ht))
    (hash-table ht)))

(defun rt-hash-table-weakness (ht)
  "Return HT's weakness mode, or NIL for ordinary strong hash tables."
  (etypecase ht
    (rt-weak-hash-table (rt-weak-hash-table-weakness ht))
    (hash-table nil)))

(defun rt-hash-table-p (x)
  (if (or (hash-table-p x) (rt-weak-hash-table-p x))
      1
      0))

(defun rt-make-hash-table (&key (test #'eql)
                                size
                                rehash-size
                                rehash-threshold
                                weakness
                                &allow-other-keys)
  "Create a runtime hash table with optional weak-key/value semantics."
  (unless (%rt-valid-hash-weakness-p weakness)
    (error "Unsupported hash-table weakness mode: ~S" weakness))
  (let ((table
         (%rt-make-backing-hash-table test
                                      size
                                      rehash-size
                                      rehash-threshold
                                      weakness)))
    (if weakness
        (let ((weak-table
               (%make-rt-weak-hash-table :table
                                         table
                                         :weakness
                                         weakness
                                         :entries
                                         (%rt-make-backing-hash-table test
                                                                      nil
                                                                      rehash-size
                                                                      rehash-threshold
                                                                      nil))))
          (pushnew weak-table *rt-weak-hash-table-registry* :test #'eq)
          weak-table)
        table)))

(defvar *rt-weak-hash-entry-hooks*
  nil)

(defun %rt-notify-weak-hash-entry-hooks (table entry)
  (dolist (hook *rt-weak-hash-entry-hooks*)
    (funcall hook table entry))
  entry)

(defun rt-register-weak-hash-entry-hook (hook)
  (check-type hook function)
  (unless (member hook *rt-weak-hash-entry-hooks* :test (function eq))
    (push hook *rt-weak-hash-entry-hooks*)
    (dolist (table *rt-weak-hash-table-registry*)
      (when (rt-weak-hash-table-p table)
        (maphash
         (lambda (key entry)
           (declare (ignore key))
           (funcall hook table entry))
         (rt-weak-hash-table-entries table)))))
  hook)

(defun %rt-record-weak-hash-entry (ht key val)
  "Record weak-entry metadata and notify registered GC processors."
  (when (rt-weak-hash-table-p ht)
    (let ((entry (make-rt-weak-hash-entry :key key :value val)))
      (setf (gethash key (rt-weak-hash-table-entries ht)) entry)
      (%rt-notify-weak-hash-entry-hooks ht entry)
      entry)))

(defun %rt-sweep-weak-hash-table (ht)
  "Drop metadata for entries no longer present in a host weak backing table."
  (when (rt-weak-hash-table-p ht)
    (let ((backing (rt-weak-hash-table-table ht))
          (entries (rt-weak-hash-table-entries ht)))
      (maphash
       (lambda (key entry)
         (declare (ignore entry))
         (unless (nth-value 1 (gethash key backing))
           (remhash key entries)))
       entries)))
  ht)

(defun rt-gethash (key ht)
  (when (rt-weak-hash-table-p ht)
    (%rt-sweep-weak-hash-table ht))
  (gethash key (%rt-hash-table-backing ht)))

(defun rt-sethash (key ht val)
  (setf (gethash key (%rt-hash-table-backing ht)) val)
  (%rt-record-weak-hash-entry ht key val)
  val)

(defun rt-remhash (key ht)
  (prog1
    (remhash key (%rt-hash-table-backing ht))
    (when (rt-weak-hash-table-p ht)
      (remhash key (rt-weak-hash-table-entries ht)))))

(defun rt-clrhash (ht)
  (clrhash (%rt-hash-table-backing ht))
  (when (rt-weak-hash-table-p ht)
    (clrhash (rt-weak-hash-table-entries ht)))
  ht)

(defun rt-hash-count (ht)
  (when (rt-weak-hash-table-p ht)
    (%rt-sweep-weak-hash-table ht))
  (hash-table-count (%rt-hash-table-backing ht)))

(defun rt-hash-size (ht)
  (when (rt-weak-hash-table-p ht)
    (%rt-sweep-weak-hash-table ht))
  (hash-table-size (%rt-hash-table-backing ht)))

(defun rt-hash-rehash-size (ht)
  (when (rt-weak-hash-table-p ht)
    (%rt-sweep-weak-hash-table ht))
  (hash-table-rehash-size (%rt-hash-table-backing ht)))

(defun rt-hash-rehash-threshold (ht)
  (when (rt-weak-hash-table-p ht)
    (%rt-sweep-weak-hash-table ht))
  (hash-table-rehash-threshold (%rt-hash-table-backing ht)))

(defun rt-hash-test (ht)
  (hash-table-test (%rt-hash-table-backing ht)))

(defun rt-maphash (fn ht)
  (when (rt-weak-hash-table-p ht)
    (%rt-sweep-weak-hash-table ht))
  (maphash fn (%rt-hash-table-backing ht)))

(defun rt-hash-keys (ht)
  (let (keys)
    (rt-maphash
     (lambda (k v)
       (declare (ignore v))
       (push k keys))
     ht)
    keys))

(defun rt-hash-values (ht)
  (let (vals)
    (rt-maphash
     (lambda (k v)
       (declare (ignore k))
       (push v vals))
     ht)
    vals))

(in-package :cl-cc/runtime/values)

(defvar *rt-weak-hash-table-registry*
  nil
  "All runtime weak hash tables.  The collector uses this metadata to remove
entries whose weak key/value has died without treating the metadata itself as a
strong reference.")

(in-package :cl-cc/runtime/values)

(defstruct (rt-weak-hash-entry (:conc-name rtwhe-))
  "Internal entry for weak hash tables. GC clears entries whose
   key or value becomes unreachable based on the weakness mode."
  key
  value
  (key-ephemeron nil)
  (value-ephemeron nil))
