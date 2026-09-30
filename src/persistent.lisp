;;;; persistent.lisp -- immutable values with structural sharing.

(in-package #:cl-cc/runtime)

(defstruct (rt-persistent-vector (:constructor %make-rt-pvector (chunks count)))
  chunks count)

(defparameter +rt-pvector-chunk-size+ 32)

(defun rt-persistent-vector (&rest values)
  (let ((chunks (make-array (ceiling (length values) +rt-pvector-chunk-size+) :initial-element nil)))
    (loop for value in values for i from 0
          do (let ((chunk-index (floor i +rt-pvector-chunk-size+)))
               (unless (aref chunks chunk-index) (setf (aref chunks chunk-index) (make-array +rt-pvector-chunk-size+)))
               (setf (aref (aref chunks chunk-index) (mod i +rt-pvector-chunk-size+)) value)))
    (%make-rt-pvector chunks (length values))))

(defun rt-persistent-vector-length (vector) (rt-persistent-vector-count vector))
(defun rt-persistent-vector-ref (vector index)
  (check-type index (integer 0))
  (when (>= index (rt-persistent-vector-count vector)) (error "Index ~D is out of bounds" index))
  (aref (aref (rt-persistent-vector-chunks vector) (floor index +rt-pvector-chunk-size+))
        (mod index +rt-pvector-chunk-size+)))

(defun rt-persistent-vector-assoc (vector index value)
  (check-type index (integer 0))
  (when (>= index (rt-persistent-vector-count vector)) (error "Index ~D is out of bounds" index))
  (let* ((chunk-index (floor index +rt-pvector-chunk-size+))
         (chunks (copy-seq (rt-persistent-vector-chunks vector)))
         (chunk (copy-seq (aref chunks chunk-index))))
    (setf (aref chunk (mod index +rt-pvector-chunk-size+)) value
          (aref chunks chunk-index) chunk)
    (%make-rt-pvector chunks (rt-persistent-vector-count vector))))

(defun rt-persistent-vector-conj (vector value)
  (let* ((count (rt-persistent-vector-count vector))
         (chunks (copy-seq (rt-persistent-vector-chunks vector)))
         (chunk-index (floor count +rt-pvector-chunk-size+)))
    (when (or (= count 0) (= (mod count +rt-pvector-chunk-size+) 0))
      (setf chunks (adjust-array chunks (1+ chunk-index) :initial-element nil)))
    (let ((chunk (if (aref chunks chunk-index)
                     (copy-seq (aref chunks chunk-index))
                     (make-array +rt-pvector-chunk-size+))))
      (setf (aref chunk (mod count +rt-pvector-chunk-size+)) value
            (aref chunks chunk-index) chunk)
      (%make-rt-pvector chunks (1+ count)))))

(defstruct (rt-persistent-map (:constructor %make-rt-pmap (root test))) root test)
(defstruct (rt-pmap-node (:constructor %make-rt-pmap-node (key value left right))) key value left right)

(defun rt-persistent-map (&key (test #'equal)) (%make-rt-pmap nil test))
(defun %rt-pmap-assoc (node key value test)
  (if (null node) (%make-rt-pmap-node key value nil nil)
      (cond ((funcall test key (rt-pmap-node-key node))
             (%make-rt-pmap-node key value (rt-pmap-node-left node) (rt-pmap-node-right node)))
            ((string< (prin1-to-string key) (prin1-to-string (rt-pmap-node-key node)))
             (%make-rt-pmap-node (rt-pmap-node-key node) (rt-pmap-node-value node)
                                 (%rt-pmap-assoc (rt-pmap-node-left node) key value test) (rt-pmap-node-right node)))
            (t (%make-rt-pmap-node (rt-pmap-node-key node) (rt-pmap-node-value node)
                                   (rt-pmap-node-left node) (%rt-pmap-assoc (rt-pmap-node-right node) key value test))))))
(defun rt-persistent-map-assoc (map key value)
  (%make-rt-pmap (%rt-pmap-assoc (rt-persistent-map-root map) key value (rt-persistent-map-test map))
                 (rt-persistent-map-test map)))
(defun rt-persistent-map-get (map key &optional default)
  (loop for node = (rt-persistent-map-root map) then (if (string< (prin1-to-string key) (prin1-to-string (rt-pmap-node-key node)))
                                                         (rt-pmap-node-left node) (rt-pmap-node-right node))
        while node do (when (funcall (rt-persistent-map-test map) key (rt-pmap-node-key node)) (return (rt-pmap-node-value node)))
        finally (return default)))
