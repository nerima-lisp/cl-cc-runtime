;;;; gc-region-collect.lisp -- mixed-collection selection and evacuation failure.
(in-package :cl-cc/runtime)

(defun %rt-gc-region-refresh (heap region)
  "Recompute REGION occupancy from mark bits after major marking."
  (let ((addr (rt-heap-region-start-word region))
        (limit (min (rt-heap-region-end-word region) (rt-heap-old-free heap)))
        (allocated 0)
        (live 0))
    (loop while (< addr limit) do
      (let ((header (rt-heap-object-header heap addr)))
        (if (and (integerp header) (plusp (rt-header-size header)))
            (let ((size (rt-header-size header)))
              (incf allocated (* size 8))
              (when (header-marked-p header)
                (incf live (* size 8)))
              (incf addr size))
            (setf addr limit))))
    (setf (rt-heap-region-allocated-bytes region) allocated
          (rt-heap-region-live-bytes region) live
          (rt-heap-region-garbage-ratio region)
          (if (zerop allocated)
              1.0d0
              (/ (float (- allocated live) 1.0d0) allocated)))))

(defun rt-gc-region-select-mixed (heap &key (max-regions 1)
                                               (min-garbage-ratio 0.1d0))
  "Refresh and select the highest-garbage old-space regions for mixed GC."
  (let ((candidates nil))
    (map nil (lambda (region)
               (%rt-gc-region-refresh heap region)
               (setf (rt-heap-region-selected-p region) nil)
               (when (and (plusp (rt-heap-region-allocated-bytes region))
                          (>= (rt-heap-region-garbage-ratio region)
                              min-garbage-ratio))
                 (push region candidates)))
         (rt-heap-regions heap))
    (loop for region in (subseq (sort candidates #'>
                                         :key #'rt-heap-region-garbage-ratio)
                                0 (min max-regions (length candidates)))
          do (setf (rt-heap-region-selected-p region) t))
    (remove-if-not #'rt-heap-region-selected-p candidates)))

(defun rt-gc-region-handle-evacuation-failure (region reason)
  "Record that REGION stayed in place because evacuation could not complete."
  (setf (rt-heap-region-evacuation-failed-p region) t)
  (list :status :failed :region region :reason reason))

(defun rt-gc-region-mixed-collect (heap &key (max-regions 1)
                                              (min-garbage-ratio 0.1d0)
                                              evacuate-fn)
  "Select mixed-collection candidates and attempt their evacuation.

EVACUATE-FN receives HEAP and REGION. A missing function is an explicit
evacuation failure, leaving the region for the normal mark-sweep fallback."
  (let ((results nil))
    (dolist (region (rt-gc-region-select-mixed
                     heap :max-regions max-regions
                     :min-garbage-ratio min-garbage-ratio))
      (push (if evacuate-fn
                (handler-case
                    (funcall evacuate-fn heap region)
                  (error (condition)
                    (rt-gc-region-handle-evacuation-failure region condition)))
                (rt-gc-region-handle-evacuation-failure
                 region :no-evacuation-target))
            results))
    (nreverse results)))
