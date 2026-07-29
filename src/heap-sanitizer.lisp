(in-package :cl-cc/runtime)

;;; ------------------------------------------------------------
;;; Sanitizer runtime toggles (FR-489..493 minimal runtime path)
;;; ------------------------------------------------------------

(defparameter *rt-asan-enabled* nil
  "When true, rt-heap-ref/set perform ASan-like poisoned-address checks.")

(defparameter *rt-msan-enabled* nil
  "When true, rt-heap-ref reports reads from uninitialized words.")

(defparameter *rt-tsan-enabled* nil
  "When true, rt-heap-set/ref perform a conservative race check using access history.")

(defparameter *rt-hwasan-enabled* nil
  "When true, rt-heap-set/ref validate heap word tags.")

(defparameter *rt-ubsan-enabled* nil
  "When true, rt-heap-set/ref perform basic undefined-behavior contract checks.")

(defparameter *rt-heap-poison-map* (make-hash-table :test #'eql)
  "Address -> T when poisoned (ASan/HWASan-like redzone marker).")

(defparameter *rt-heap-init-map* (make-hash-table :test #'eql)
  "Address -> T when initialized (MSan-like state).")

(defparameter *rt-heap-tag-map* (make-hash-table :test #'eql)
  "Address -> 4-bit heap tag (HWASan-like metadata).")

(progn
  (defparameter *rt-heap-access-map* (make-hash-table :test #'eql)
    "Address -> vector-clock access history used by TSan checks.")
  (defparameter *rt-tsan-thread-clocks* (make-hash-table :test #'eql))
  (defparameter *rt-tsan-sync-clocks* (make-hash-table :test #'eq))
  (defparameter *rt-tsan-host-thread-ids* (make-hash-table :test #'eq))
  (defparameter *rt-tsan-next-thread-id* 1))

(defparameter *rt-tsan-thread-id* nil
  "Optional logical thread id override; NIL assigns a stable host-thread id.")

(defun %rt-sanitizer-sb-thread-function (name)
  "Return the SB-THREAD function named NAME, or NIL when unavailable."
  (ignore-errors
    (let ((package (find-package "SB-THREAD")))
      (when package
        (multiple-value-bind (symbol status) (find-symbol name package)
          (when (and status (fboundp symbol))
            (symbol-function symbol)))))))

(defun %rt-sanitizer-make-mutex ()
  "Create an optional mutex for sanitizer bookkeeping maps."
  (let ((make-mutex (%rt-sanitizer-sb-thread-function "MAKE-MUTEX")))
    (and make-mutex (ignore-errors (funcall make-mutex :name "rt-sanitizer-maps")))))

(defvar *rt-sanitizer-map-lock* (%rt-sanitizer-make-mutex)
  "Optional lock protecting global sanitizer hash tables during parallel tests.")

(defmacro %rt-with-sanitizer-map-lock (() &body body)
  (let ((fn (gensym "CALL-WITH-MUTEX"))
        (lock (gensym "LOCK")))
    `(let ((,lock *rt-sanitizer-map-lock*))
       (if ,lock
           (let ((,fn (%rt-sanitizer-sb-thread-function "CALL-WITH-MUTEX")))
             (if ,fn
                 (funcall ,fn (lambda () ,@body) ,lock)
                 (progn ,@body)))
           (progn ,@body)))))

(defun rt-sanitizer-reset-state ()
  "Reset sanitizer bookkeeping maps to empty state."
  (%rt-with-sanitizer-map-lock ()
    (clrhash *rt-heap-poison-map*)
    (clrhash *rt-heap-init-map*)
    (clrhash *rt-heap-tag-map*)
    (clrhash *rt-heap-access-map*)
    (clrhash *rt-tsan-thread-clocks*)
    (clrhash *rt-tsan-sync-clocks*)
    (clrhash *rt-tsan-host-thread-ids*)
    (setf *rt-tsan-next-thread-id* 1))
  t)

(defun rt-sanitizer-poison-address (index)
  "Mark INDEX as poisoned for ASan/HWASan checks."
  (%rt-with-sanitizer-map-lock ()
    (setf (gethash index *rt-heap-poison-map*) t))
  t)

(defun rt-sanitizer-unpoison-address (index)
  "Clear poison marker from INDEX."
  (%rt-with-sanitizer-map-lock ()
    (remhash index *rt-heap-poison-map*))
  t)

(defun rt-sanitizer-set-address-tag (index tag)
  "Set 4-bit HWASan tag for INDEX."
  (%rt-with-sanitizer-map-lock ()
    (setf (gethash index *rt-heap-tag-map*) (logand tag #xF)))
  t)

(defun %rt-asan-check-address (heap index op)
  (let ((limit (length (rt-heap-words heap))))
    (when (or (< index 0) (>= index limit))
      (error "ASan: ~A out-of-bounds heap access at ~D (limit ~D)" op index limit))
    (%rt-with-sanitizer-map-lock ()
      (when (gethash index *rt-heap-poison-map*)
        (error "ASan: ~A on poisoned heap address ~D" op index)))))

(defun %rt-msan-check-read (index)
  (when *rt-msan-enabled*
    (%rt-with-sanitizer-map-lock ()
      (when (null (gethash index *rt-heap-init-map*))
        (error "MSan: read from uninitialized heap address ~D" index)))))

(progn
  (defun %rt-tsan-current-thread-id ()
    (or *rt-tsan-thread-id*
        (let ((thread sb-thread:*current-thread*))
          (or (gethash thread *rt-tsan-host-thread-ids*)
              (setf (gethash thread *rt-tsan-host-thread-ids*)
                    (prog1 *rt-tsan-next-thread-id*
                      (incf *rt-tsan-next-thread-id*)))))))

  (defun %rt-tsan-clock (thread-id)
    (or (gethash thread-id *rt-tsan-thread-clocks*)
        (setf (gethash thread-id *rt-tsan-thread-clocks*)
              (make-hash-table :test #'eql))))

  (defun %rt-tsan-copy-clock (clock)
    (let ((copy (make-hash-table :test #'eql)))
      (maphash (lambda (thread-id value) (setf (gethash thread-id copy) value)) clock)
      copy))

  (defun %rt-tsan-tick (thread-id clock)
    (setf (gethash thread-id clock) (1+ (gethash thread-id clock 0))))

  (defun %rt-tsan-merge-clock (clock other)
    (maphash (lambda (thread-id value)
               (setf (gethash thread-id clock) (max value (gethash thread-id clock 0))))
             other))

  (defun %rt-tsan-happens-before-p (event clock)
    (destructuring-bind (thread-id event-clock mode) event
      (declare (ignore mode))
      (<= (gethash thread-id event-clock 0) (gethash thread-id clock 0))))

  (defun %rt-tsan-race (index previous thread-id mode)
    (error "TSan: data race at heap address ~D between thread ~D (~A) and ~D (~A)"
           index (first previous) (third previous) thread-id mode))

  (defun rt-tsan-acquire (object)
    (when *rt-tsan-enabled*
      (%rt-with-sanitizer-map-lock ()
        (let* ((thread-id (%rt-tsan-current-thread-id))
               (clock (%rt-tsan-clock thread-id))
               (released (gethash object *rt-tsan-sync-clocks*)))
          (when released (%rt-tsan-merge-clock clock released))
          (%rt-tsan-tick thread-id clock))))
    t)

  (defun rt-tsan-release (object)
    (when *rt-tsan-enabled*
      (%rt-with-sanitizer-map-lock ()
        (let* ((thread-id (%rt-tsan-current-thread-id))
               (clock (%rt-tsan-clock thread-id)))
          (%rt-tsan-tick thread-id clock)
          (setf (gethash object *rt-tsan-sync-clocks*) (%rt-tsan-copy-clock clock)))))
    t)

  (defun %rt-tsan-check-event (index event clock thread-id mode)
    (when (and event
               (/= (first event) thread-id)
               (not (%rt-tsan-happens-before-p event clock)))
      (%rt-tsan-race index event thread-id mode)))

  (defun %rt-tsan-check-access (index mode)
    (when *rt-tsan-enabled*
      (%rt-with-sanitizer-map-lock ()
        (let* ((thread-id (%rt-tsan-current-thread-id))
               (clock (%rt-tsan-clock thread-id))
               (state (or (gethash index *rt-heap-access-map*)
                          (setf (gethash index *rt-heap-access-map*)
                                (cons nil (make-hash-table :test #'eql))))))
          (%rt-tsan-tick thread-id clock)
          (%rt-tsan-check-event index (car state) clock thread-id mode)
          (when (eq mode :write)
            (maphash (lambda (reader-id event)
                       (declare (ignore reader-id))
                       (%rt-tsan-check-event index event clock thread-id mode))
                     (cdr state)))
          (let ((event (list thread-id (%rt-tsan-copy-clock clock) mode)))
            (if (eq mode :write)
                (progn (setf (car state) event) (clrhash (cdr state)))
                (setf (gethash thread-id (cdr state)) event))))))))

(defun %rt-hwasan-check-address (index expected-tag)
  (when *rt-hwasan-enabled*
    (%rt-with-sanitizer-map-lock ()
      (let ((actual-tag (gethash index *rt-heap-tag-map* 0)))
        (unless (= (logand expected-tag #xF) actual-tag)
          (error "HWASan: tag mismatch at heap address ~D (expected ~D, actual ~D)"
                 index (logand expected-tag #xF) actual-tag))))))

(defun %rt-ubsan-check-access (heap index op)
  (when *rt-ubsan-enabled*
    (unless (integerp index)
      (error "UBSan: ~A requires integer heap index, got ~S" op index))
    (when (< index 0)
      (error "UBSan: ~A uses negative heap index ~D" op index))
    (when (>= index (length (rt-heap-words heap)))
      (error "UBSan: ~A out-of-bounds heap index ~D" op index))))
