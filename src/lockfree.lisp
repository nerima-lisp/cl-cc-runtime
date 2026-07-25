;;;; Lock-Free Data Structures (FR-322)
(in-package :cl-cc/runtime)

(defstruct rt-lfstack-node
  (value nil)
  (next nil))

(defstruct rt-lfstack
  (top nil))

(defun rt-make-lfstack ()
  (make-rt-lfstack))

(defun rt-lfstack-push (s v)
  "Push V onto S via a real atomic compare-and-swap retry loop."
  (loop for old = (rt-lfstack-top s)
        for node = (make-rt-lfstack-node :value v :next old)
        until (eq (sb-ext:cas (rt-lfstack-top s) old node) old))
  v)

(defun rt-lfstack-pop (s)
  "Pop and return (VALUES value t) from S, or (VALUES nil nil) when empty.
Uses a real atomic compare-and-swap retry loop."
  (loop for top = (rt-lfstack-top s)
        do (unless top (return (values nil nil)))
           (when (eq (sb-ext:cas (rt-lfstack-top s) top (rt-lfstack-node-next top)) top)
             (return (values (rt-lfstack-node-value top) t)))))

(defun rt-lfstack-empty-p (s)
  (null (rt-lfstack-top s)))

(defstruct rt-lfqueue-node
  (value nil)
  (next nil))

(defstruct rt-lfqueue
  (head nil)
  (tail nil)
  (mutex (rt-make-mutex)))

(defun rt-make-lfqueue ()
  (let ((d (make-rt-lfqueue-node)))
    (make-rt-lfqueue :head d :tail d)))

(defun rt-lfqueue-push (q v)
  (rt-with-mutex ((rt-lfqueue-mutex q))
    (let ((n (make-rt-lfqueue-node :value v)))
      (setf (rt-lfqueue-node-next (rt-lfqueue-tail q)) n)
      (setf (rt-lfqueue-tail q) n)))
  v)

(defun rt-lfqueue-pop (q)
  (rt-with-mutex ((rt-lfqueue-mutex q))
    (let ((n (rt-lfqueue-node-next (rt-lfqueue-head q))))
      (when n
        (setf (rt-lfqueue-head q) n)
        (values (rt-lfqueue-node-value n) t)))))

(defun rt-lfqueue-empty-p (q)
  (null (rt-lfqueue-node-next (rt-lfqueue-head q))))

(defstruct rt-lfhash-entry
  (key nil)
  (value nil)
  (deleted-p nil)
  (next nil))

(defstruct rt-lfhash-map
  (buckets (make-array 64 :initial-element nil))
  (count 0 :type (unsigned-byte 64))
  (test #'eql)
  (mutex (rt-make-mutex)))

(defun rt-make-lfhash-map (&key (test 'eql) (size 64))
  (make-rt-lfhash-map
   :buckets (make-array (max 2 size) :initial-element nil)
   :test (etypecase test
           (symbol (symbol-function test))
           (function test))))

(defun %rt-lfhash-index (m k)
  (mod (sxhash k) (length (rt-lfhash-map-buckets m))))

(defun %rt-lfhash-find (m k)
  (let ((test (rt-lfhash-map-test m)))
    (loop for e = (svref (rt-lfhash-map-buckets m) (%rt-lfhash-index m k))
            then (rt-lfhash-entry-next e)
          while e
          when (and (not (rt-lfhash-entry-deleted-p e))
                    (funcall test k (rt-lfhash-entry-key e)))
            do (return e))))

(defun rt-lfhash-get (m k &optional d)
  (let ((e (%rt-lfhash-find m k)))
    (if e
        (values (rt-lfhash-entry-value e) t)
        (values d nil))))

(defun rt-lfhash-put (m k v)
  "Insert or update K/V in M. New-entry bucket insertion is a real atomic
compare-and-swap retry loop on the bucket head."
  (loop
    (let ((existing (%rt-lfhash-find m k)))
      (when existing
        (setf (rt-lfhash-entry-value existing) v)
        (return v)))
    (let* ((idx (%rt-lfhash-index m k))
           (buckets (rt-lfhash-map-buckets m))
           (head (svref buckets idx))
           (entry (make-rt-lfhash-entry :key k :value v :next head)))
      (when (eq (sb-ext:cas (svref buckets idx) head entry) head)
        (sb-ext:atomic-incf (rt-lfhash-map-count m))
        (return v)))))

(defun rt-lfhash-remove (m k)
  (let ((e (%rt-lfhash-find m k)))
    (when e
      (setf (rt-lfhash-entry-deleted-p e) t)
      (sb-ext:atomic-decf (rt-lfhash-map-count m))
      t)))

(defun rt-lfhash-cas (m k old new)
  (let ((e (%rt-lfhash-find m k)))
    (cond
      ((and e (eql (rt-lfhash-entry-value e) old))
       (setf (rt-lfhash-entry-value e) new)
       t)
      ((and (null e) (null old))
       (rt-lfhash-put m k new)
       t)
      (t nil))))

(defun rt-lfhash-count (m)
  (rt-lfhash-map-count m))

(defun rt-lockfree-init ()
  t)
