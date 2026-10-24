;;;; runtime-code-cache.lisp — JIT code cache (FR-379/FR-437), split out of
;;;; runtime-conditions.lisp, which it has no thematic relation to
(in-package :cl-cc/runtime)

;;; ------------------------------------------------------------
;;; JIT Code Cache Management (FR-379 / FR-437)
;;; ------------------------------------------------------------

(defstruct (rt-code-cache-entry (:conc-name rt-code-cache-entry-))
  function-entry
  code
  (size 1 :type integer)
  (warmth 0 :type integer)
  (last-used 0 :type integer)
  class-key
  reachable-p)

(defstruct (rt-code-cache (:constructor make-rt-code-cache
                              (&key (capacity 1024)
                                     (entries (make-hash-table :test #'equal))
                                     (lru-clock 0)
                                     (size 0)
                                     (eviction-threshold 0.9)
                                     (hits 0)
                                     (misses 0)
                                     (evictions 0))))
  (capacity 1024 :type integer)
  (entries (make-hash-table :test #'equal) :type hash-table)
  (lru-clock 0 :type integer)
  (size 0 :type integer)
  (eviction-threshold 0.9 :type real)
  (hits 0 :type integer)
  (misses 0 :type integer)
  (evictions 0 :type integer))

(defparameter *rt-code-cache* (make-rt-code-cache)
  "Global runtime JIT code cache.

Evicted compiled code is deliberately removed only from this cache.  Runtime
callers should fall back to bytecode interpretation or recompilation when a
function entry no longer has a compiled-code cache entry.")

(defun rt-code-cache-lookup (function-entry &optional (cache *rt-code-cache*))
  "Return compiled code for FUNCTION-ENTRY and refresh its LRU timestamp."
  (let ((entry (gethash function-entry (rt-code-cache-entries cache))))
    (if entry
        (progn
          (incf (rt-code-cache-hits cache))
          (incf (rt-code-cache-lru-clock cache))
          (incf (rt-code-cache-entry-warmth entry))
          (setf (rt-code-cache-entry-last-used entry) (rt-code-cache-lru-clock cache))
          (rt-code-cache-entry-code entry))
        (progn
          (incf (rt-code-cache-misses cache))
          nil))))

(defun rt-code-cache-evict (function-entry &optional (cache *rt-code-cache*))
  "Evict FUNCTION-ENTRY from CACHE and return the evicted entry, if present.

After eviction, callers are expected to fall back to interpretation until the
function is compiled again."
  (let ((entry (gethash function-entry (rt-code-cache-entries cache))))
    (when entry
      (remhash function-entry (rt-code-cache-entries cache))
      (decf (rt-code-cache-size cache) (rt-code-cache-entry-size entry))
      (incf (rt-code-cache-evictions cache))
      ;; Host Lisp owns ordinary code objects; dropping references is the free path.
      (setf (rt-code-cache-entry-code entry) nil
            (rt-code-cache-entry-reachable-p entry) nil)
      entry)))

(defun %rt-code-cache-coldest-entry (cache)
  (let ((oldest-key nil)
        (oldest-entry nil))
    (maphash (lambda (key entry)
                (when (or (null oldest-entry)
                          (< (rt-code-cache-entry-warmth entry)
                             (rt-code-cache-entry-warmth oldest-entry))
                          (and (= (rt-code-cache-entry-warmth entry)
                                  (rt-code-cache-entry-warmth oldest-entry))
                          (< (rt-code-cache-entry-last-used entry)
                                (rt-code-cache-entry-last-used oldest-entry))))
                  (setf oldest-key key
                        oldest-entry entry)))
              (rt-code-cache-entries cache))
    (values oldest-key oldest-entry)))

(defun %rt-code-cache-evict-until-room (cache requested-size)
  (let* ((capacity (rt-code-cache-capacity cache))
         (threshold-size (max requested-size
                              (floor (* capacity (rt-code-cache-eviction-threshold cache))))))
    (loop while (or (> (+ (rt-code-cache-size cache) requested-size) capacity)
                    (> (+ (rt-code-cache-size cache) requested-size) threshold-size))
          do (multiple-value-bind (key entry) (%rt-code-cache-coldest-entry cache)
               (declare (ignore entry))
               (unless key (return))
               (rt-code-cache-evict key cache)))))

(defun rt-code-cache-store (function-entry code &key (size 1) class-key
                                          (cache *rt-code-cache*))
  "Store CODE for FUNCTION-ENTRY, evicting least-recently-used entries as needed."
  (check-type size (integer 0 *))
  (let ((old-entry (gethash function-entry (rt-code-cache-entries cache))))
    (when old-entry
      (decf (rt-code-cache-size cache) (rt-code-cache-entry-size old-entry)))
    (%rt-code-cache-evict-until-room cache size)
    (incf (rt-code-cache-lru-clock cache))
    (let ((entry (make-rt-code-cache-entry
                  :function-entry function-entry
                   :code code
                   :size size
                   :warmth 1
                   :last-used (rt-code-cache-lru-clock cache)
                  :class-key class-key
                  :reachable-p t)))
      (setf (gethash function-entry (rt-code-cache-entries cache)) entry)
      (incf (rt-code-cache-size cache) size)
      entry)))

(defun rt-code-cache-stats (&optional (cache *rt-code-cache*))
  "Return a plist of code-cache occupancy, hit-rate, and eviction counters."
  (let* ((hits (rt-code-cache-hits cache))
         (misses (rt-code-cache-misses cache))
         (total (+ hits misses)))
    (list :size (rt-code-cache-size cache)
          :capacity (rt-code-cache-capacity cache)
          :threshold (rt-code-cache-eviction-threshold cache)
          :entries (hash-table-count (rt-code-cache-entries cache))
          :hits hits
          :misses misses
          :hit-rate (if (plusp total) (/ hits total) 0.0)
          :evictions (rt-code-cache-evictions cache))))

(defun rt-gc-unload-code (heap code-addr &optional (cache *rt-code-cache*))
  "Unload compiled code CODE-ADDR from the JIT cache.

HEAP is accepted for GC integration symmetry and currently not inspected.  The
evicted function will fall back to interpretation if called later."
  (declare (ignore heap))
  (or (rt-code-cache-evict code-addr cache)
      (let (keys removed)
        (maphash (lambda (key entry)
                   (when (eql (rt-code-cache-entry-code entry) code-addr)
                     (push key keys)))
                 (rt-code-cache-entries cache))
        (dolist (key keys)
          (push (rt-code-cache-evict key cache) removed))
        (nreverse removed))))
