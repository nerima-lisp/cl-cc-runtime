;;;; gc-weak-processing.lisp — Ephemerons, weak hash tables, and the GC-time
;;;; processing passes over the reference types in gc-references.lisp
(in-package :cl-cc/runtime)

;;; ------------------------------------------------------------
;;; Ephemerons (FR-246) — key-value pairs where value is only
;;; reachable if the key is reachable
;;; ------------------------------------------------------------

(defstruct (rt-ephemeron (:constructor %make-rt-ephemeron))
  "An ephemeron: a key-value pair where the value is only considered
   reachable if the key itself is reachable. Used for weak hash tables."
  key
  value
  (marked nil :type boolean))

(defvar *rt-ephemeron-registry* nil
  "Global registry of all ephemerons for GC processing.")

(defun rt-make-ephemeron (key value)
  "Create an ephemeron with KEY and VALUE."
  (let ((eph (%make-rt-ephemeron :key key :value value)))
    (push eph *rt-ephemeron-registry*)
    eph))

;;; ------------------------------------------------------------
;;; GC Reference Processing (FR-381-384, FR-337, FR-459-460)
;;; Called during major GC after marking, before sweep
;;; ------------------------------------------------------------

(defun %rt-gc-process-soft-references (heap marked-set)
  "Clear soft references whose referents are not marked, but ONLY when
   heap occupancy exceeds the pressure threshold. Soft refs are the most
   resilient reference type — they survive until memory pressure is high."
  (when (>= (rt-heap-occupancy-pct heap) 80.0d0)
    (dolist (ref *rt-reference-registry*)
      (when (rt-soft-ref-p ref)
        (let ((referent (rt-soft-ref-referent ref)))
          (when (and referent
                     (not (%rt-gc-reference-live-p heap marked-set referent)))
            (%rt-reference-clear ref)))))))

(defun %rt-gc-process-weak-references (heap marked-set)
  "Clear weak references whose referents are NOT marked (unreachable).
   Weak refs are always cleared when their referent is unreachable."
  (dolist (ref *rt-reference-registry*)
    (when (rt-weak-ref-p ref)
      (let ((referent (rt-weak-ref-referent ref)))
        (when (and referent
                   (not (%rt-gc-reference-live-p heap marked-set referent)))
          (%rt-reference-clear ref))))))

(defun %rt-gc-process-phantom-references (heap marked-set)
  "Enqueue phantom references whose referents are collected.
   Phantom refs are enqueued after the referent is finalized and collected."
  (dolist (ref *rt-reference-registry*)
    (when (rt-phantom-ref-p ref)
      (let ((referent (rt-phantom-ref-referent ref)))
        (when (and referent
                   (not (%rt-gc-reference-live-p heap marked-set referent))
                   (not (rt-phantom-ref-enqueued ref)))
          (%rt-reference-clear ref))))))

(defun %rt-gc-process-ephemerons (heap marked-set)
  "Process ephemerons: mark values whose keys are marked.
   Uses fixed-point iteration because ephemerons can form chains:
   eph1.key → marked → eph1.value marked → (if eph2.key = eph1.value) → eph2.value marked"
  (dolist (eph *rt-ephemeron-registry*)
    (setf (rt-ephemeron-marked eph) nil))
  (loop with changed = t
        while changed
        do (setf changed nil)
           (dolist (eph *rt-ephemeron-registry*)
             (unless (rt-ephemeron-marked eph)
                (when (%rt-gc-reference-live-p heap marked-set (rt-ephemeron-key eph))
                  (setf (rt-ephemeron-marked eph) t)
                  (%rt-gc-mark-reference-value heap marked-set (rt-ephemeron-value eph))
                  (setf changed t))))))

(defun rt-gc-process-references (heap marked-set)
  "Process all reference types during major GC after the mark phase.
   Order matters: ephemerons first (may mark additional objects),
   then soft refs (pressure-dependent), weak refs, phantom refs."
  (%rt-gc-process-ephemerons heap marked-set)
  (%rt-gc-process-soft-references heap marked-set)
  (%rt-gc-process-weak-references heap marked-set)
  (%rt-gc-process-weak-hash-tables heap marked-set))

;;; ------------------------------------------------------------
;;; Weak Hash Table Support (FR-448, FR-449)
;;; ------------------------------------------------------------

(defun %rt-weak-entry-dead-p (weakness key-live-p value-live-p)
  "Return true when a weak-hash entry must be removed under WEAKNESS given liveness."
  (case weakness
    (:key (not key-live-p))
    (:value (not value-live-p))
    (:key-and-value (and (not key-live-p) (not value-live-p)))
    (:key-or-value (or (not key-live-p) (not value-live-p)))
    (otherwise nil)))

(defstruct (rt-weak-hash-entry (:conc-name rtwhe-))
  "Internal entry for weak hash tables. GC clears entries whose
   key or value becomes unreachable based on the weakness mode."
  key
  value
  (key-ephemeron nil)
  (value-ephemeron nil))

(defun %rt-gc-mark-reference-value (heap marked-set value)
  "Mark VALUE and its strong outgoing graph during ephemeron processing."
  (let ((addr (%rt-gc-reference-value-address heap value)))
    (when (and addr (not (gethash addr marked-set)))
      (setf (gethash addr marked-set) t)
      (when (and (rt-old-addr-p heap addr)
                 (fboundp '%rt-gc-grey-object)
                 (fboundp '%rt-gc-drain-major-mark-work))
        (let ((queue-cell (cons nil nil)))
          (%rt-gc-grey-object heap queue-cell addr)
          (%rt-gc-drain-major-mark-work heap queue-cell)
          ;; The drain marks transitively; refresh the visible set for weak
          ;; processing without consuming mark bits.
          (maphash (lambda (k v) (declare (ignore v))
                     (setf (gethash k marked-set) t))
                   (%rt-gc-build-marked-set heap))))))
  marked-set)

(defun %rt-gc-process-weak-hash-tables (heap marked-set)
  "Remove weak hash entries whose key/value liveness violates their weakness."
  (dolist (ht *rt-weak-hash-table-registry*)
    (when (rt-weak-hash-table-p ht)
      (let ((backing (rt-weak-hash-table-table ht))
            (entries (rt-weak-hash-table-entries ht))
            (weakness (rt-weak-hash-table-weakness ht))
            (dead-keys nil))
        (maphash
         (lambda (metadata-key entry)
           (let* ((key (rtwhe-key entry))
                  (value (rtwhe-value entry))
                  (key-live-p (%rt-gc-reference-live-p heap marked-set key))
                  (value-live-p (%rt-gc-reference-live-p heap marked-set value))
                  (remove-p (%rt-weak-entry-dead-p weakness key-live-p value-live-p)))
             (when remove-p
               (remhash key backing)
               (push metadata-key dead-keys))))
         entries)
        (dolist (key dead-keys)
          (remhash key entries)))))
  *rt-weak-hash-table-registry*)

(defun %rt-gc-forwarded-value-after-minor (heap value in-source-p)
  "Return (values NEW-VALUE LIVE-IN-SOURCE-P) for a weak referent after minor GC."
  (let ((addr (%rt-gc-value-address-for-predicate value in-source-p)))
    (if (null addr)
        (values value t)
        (let ((h (rt-heap-object-header heap addr)))
          (if (header-forwarding-p h)
              (values (%rt-gc-rebox-pointer-like value (header-forwarding-ptr h)) t)
              (values nil nil))))))

(defun rt-gc-process-weak-after-minor (heap in-source-p)
  "Update or clear weak references after young-generation evacuation."
  (dolist (ref *rt-reference-registry*)
      (when (rt-weak-ref-p ref)
        (let ((referent (rt-weak-ref-referent ref)))
          (when referent
            (multiple-value-bind (new live-p)
                (%rt-gc-forwarded-value-after-minor heap referent in-source-p)
              (if live-p
                  (setf (rt-weak-ref-referent ref) new)
                  (%rt-reference-clear ref)))))))
  (dolist (ht *rt-weak-hash-table-registry*)
      (when (rt-weak-hash-table-p ht)
        (let ((backing (rt-weak-hash-table-table ht))
              (entries (rt-weak-hash-table-entries ht))
              (dead-keys nil)
              (updates nil))
          (maphash
           (lambda (metadata-key entry)
             (multiple-value-bind (new-key key-live-p)
                 (%rt-gc-forwarded-value-after-minor heap (rtwhe-key entry) in-source-p)
               (multiple-value-bind (new-value value-live-p)
                   (%rt-gc-forwarded-value-after-minor heap (rtwhe-value entry) in-source-p)
                 (let* ((weakness (rt-weak-hash-table-weakness ht))
                        (remove-p (%rt-weak-entry-dead-p weakness key-live-p value-live-p)))
                   (if remove-p
                       (progn
                         (remhash (rtwhe-key entry) backing)
                         (push metadata-key dead-keys))
                       (progn
                         (setf (rtwhe-key entry) new-key
                               (rtwhe-value entry) new-value)
                         (push (list metadata-key new-key new-value entry) updates)))))))
           entries)
          (dolist (key dead-keys)
            (remhash key entries))
          (dolist (update updates)
            (destructuring-bind (old-key new-key new-value entry) update
              (unless (eql old-key new-key)
                (remhash old-key entries)
                (remhash old-key backing))
              (setf (gethash new-key entries) entry
                    (gethash new-key backing) new-value))))))
  heap)
