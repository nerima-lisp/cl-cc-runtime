;;;; image-core-graph.lisp — Position-independent object-graph encoding and
;;;; decoding for core image save/load (src/image-core-persist.lisp)
(in-package :cl-cc/runtime)

(defun %rt-core-encode-graph (roots)
  "Copy reachable heap objects from ROOTS into a position-independent graph."
  (let ((forwarding (make-hash-table :test #'eq))
        (nodes nil)
        (next-id 0))
    (labels ((object-id (object)
               (multiple-value-bind (id presentp) (gethash object forwarding)
                 (if presentp
                     id
                     (let ((new-id next-id))
                       (incf next-id)
                       (setf (gethash object forwarding) new-id)
                       new-id))))
             (host-function-key (fn)
               (or (%rt-core-function-name-token fn)
                   (let ((key (format nil "host-closure-~36R" (sxhash fn))))
                     (setf (gethash key *rt-core-function-registry*) fn)
                     key)))
             (encode (object)
               (cond
                 ((null object) '(:immediate :nil))
                 ((eq object t) '(:immediate :t))
                 ((or (numberp object) (characterp object) (stringp object))
                  (list :immediate object))
                 ((symbolp object) (list :symbol (%rt-core-symbol-token object)))
                 ((or (consp object) (vectorp object) (hash-table-p object)
                      (functionp object) (typep object 'standard-object))
                  (let ((known (gethash object forwarding)))
                    (when known (return-from encode (list :ref known))))
                  (let ((id (object-id object)))
                    (cond
                      ((consp object)
                       (push (list :node id :cons
                                   (encode (car object)) (encode (cdr object)))
                             nodes))
                      ((vectorp object)
                       (push (list :node id :vector (map 'list #'encode object)) nodes))
                      ((hash-table-p object)
                       (let ((entries nil))
                         (maphash (lambda (k v) (push (list (encode k) (encode v)) entries)) object)
                         (push (list :node id :hash (hash-table-test object)
                                     (nreverse entries))
                               nodes)))
                      ((functionp object)
                       (push (list :node id :function (host-function-key object)) nodes))
                      ((typep object 'standard-object)
                       (let ((slots nil))
                         (dolist (slot (%rt-core-class-slot-names object))
                           (push (list slot
                                       (slot-boundp object slot)
                                       (when (slot-boundp object slot)
                                         (encode (slot-value object slot))))
                                 slots))
                         (push (list :node id :instance
                                     (%rt-core-symbol-token (class-name (class-of object)))
                                     (nreverse slots))
                               nodes))))
                    (list :ref id)))
                 (t
                  (list :unreadable (type-of object) (prin1-to-string object))))))
      (let ((encoded-roots (mapcar (lambda (entry)
                                     (destructuring-bind (name value) entry
                                       (list name (encode value))))
                                   roots)))
        (list :roots encoded-roots
              :nodes (sort (copy-list nodes) #'< :key #'second)
              :object-count next-id)))))

(defun %rt-core-decode-graph (graph)
  "Restore a graph produced by %RT-CORE-ENCODE-GRAPH and fix internal offsets."
  (let* ((nodes (getf graph :nodes))
         (objects (make-hash-table :test #'eql)))
    (labels ((placeholder (node)
               (destructuring-bind (_ id kind &rest payload) node
                 (declare (ignore _))
                 (setf (gethash id objects)
                       (case kind
                         (:cons (cons nil nil))
                         (:vector (make-array (length (first payload))))
                         (:hash (make-hash-table :test (or (first payload) 'eql)))
                         (:instance
                          (allocate-instance
                           (find-class (%rt-core-token-symbol (first payload)))))
                         (:function (let ((key (first payload)))
                                      (cond
                                        ((consp key) (symbol-function (%rt-core-token-symbol key)))
                                        (t
                                         (multiple-value-bind (fn presentp)
                                             (gethash key *rt-core-function-registry*)
                                           (if presentp
                                               fn
                                               ((lambda (missing-key)
                                                  (lambda (&rest args)
                                                    (declare (ignore args))
                                                    (error "Saved host closure is unavailable: ~A"
                                                           missing-key)))
                                                key)))))))
                         (otherwise nil)))))
             (resolve (form)
               (case (first form)
                 (:immediate (if (eq (second form) :nil)
                                 nil
                                 (if (eq (second form) :t) t (second form))))
                 (:symbol (%rt-core-token-symbol (second form)))
                 (:ref (gethash (second form) objects))
                 (:unreadable nil)
                 (otherwise form)))
             (fill-node (node)
               (destructuring-bind (_ id kind &rest payload) node
                 (declare (ignore _))
                 (let ((object (gethash id objects)))
                   (case kind
                     (:cons
                      (setf (car object) (resolve (first payload))
                            (cdr object) (resolve (second payload))))
                     (:vector
                      (loop for item in (first payload)
                            for i from 0
                            do (setf (aref object i) (resolve item))))
                     (:hash
                      (dolist (entry (second payload))
                        (setf (gethash (resolve (first entry)) object)
                              (resolve (second entry)))))
                     (:instance
                      (dolist (slot-entry (second payload))
                        (destructuring-bind (slot-name boundp encoded) slot-entry
                          (when boundp
                            (setf (slot-value object slot-name) (resolve encoded)))))))))))
      (dolist (node nodes) (placeholder node))
      (dolist (node nodes) (fill-node node))
      (mapcar (lambda (entry)
                (destructuring-bind (name encoded) entry
                  (list name (resolve encoded))))
              (getf graph :roots)))))
