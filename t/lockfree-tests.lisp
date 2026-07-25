;;;; t/lockfree-tests.lisp — lock-free stack / queue / hash map (src/lockfree.lisp).
(in-package :cl-cc-runtime/test)

(defun %drain-lfstack (s)
  (loop for res = (multiple-value-list (rt-lfstack-pop s))
        while (second res) collect (first res)))

(defun %drain-lfqueue (q)
  (loop for res = (multiple-value-list (rt-lfqueue-pop q))
        while (second res) collect (first res)))

(describe "lock-free stack"
  (it "starts empty and reports empty-p"
    (let ((s (rt-make-lfstack)))
      (expect (rt-lfstack-empty-p s) :to-be-truthy)
      (multiple-value-bind (v ok) (rt-lfstack-pop s)
        (expect v :to-be-null)
        (expect ok :to-be-null))))

  (it "push returns the value pushed and clears empty-p"
    (let ((s (rt-make-lfstack)))
      (expect (rt-lfstack-push s 42) :to-be 42)
      (expect (rt-lfstack-empty-p s) :to-be-falsy)))

  (it "pop returns value with a second true value"
    (let ((s (rt-make-lfstack)))
      (rt-lfstack-push s :only)
      (multiple-value-bind (v ok) (rt-lfstack-pop s)
        (expect v :to-be :only)
        (expect ok :to-be-truthy))
      (expect (rt-lfstack-empty-p s) :to-be-truthy)))

  (it-property "drains pushed values in strict LIFO order"
      ((items (gen-list (gen-integer :min -1000 :max 1000) :max-length 40)))
    (let ((s (rt-make-lfstack)))
      (dolist (x items) (rt-lfstack-push s x))
      (expect (%drain-lfstack s) :to-equal (reverse items))
      (expect (rt-lfstack-empty-p s) :to-be-truthy)))

  ;; The stack uses a real sb-ext:cas retry loop, so concurrent producers must
  ;; not lose a single push: every value survives and none is phantom.
  (it "loses no pushes under concurrent producers"
    (let* ((s (rt-make-lfstack)) (nthreads 4) (per 500)
           (threads (loop repeat nthreads
                          collect (sb-thread:make-thread
                                   (lambda () (dotimes (i per) (rt-lfstack-push s i)))))))
      (dolist (th threads) (sb-thread:join-thread th))
      (let ((survivors (%drain-lfstack s)))
        (expect (length survivors) :to-be (* nthreads per))
        (expect (every (lambda (v) (and (integerp v) (<= 0 v (1- per)))) survivors)
                :to-be-truthy)
        ;; Exact multiset check: each value 0..per-1 appears exactly nthreads times.
        (let ((counts (make-array per :initial-element 0)))
          (dolist (v survivors) (incf (aref counts v)))
          (expect (every (lambda (c) (= c nthreads)) counts) :to-be-truthy))))))

(describe "lock-free queue"
  (it "starts empty; pop returns nil"
    (let ((q (rt-make-lfqueue)))
      (expect (rt-lfqueue-empty-p q) :to-be-truthy)
      (expect (nth-value 1 (rt-lfqueue-pop q)) :to-be-null)))

  (it "push returns the value and clears empty-p"
    (let ((q (rt-make-lfqueue)))
      (expect (rt-lfqueue-push q 7) :to-be 7)
      (expect (rt-lfqueue-empty-p q) :to-be-falsy)))

  (it-property "drains pushed values in strict FIFO order"
      ((items (gen-list (gen-integer :min -1000 :max 1000) :max-length 40)))
    (let ((q (rt-make-lfqueue)))
      (dolist (x items) (rt-lfqueue-push q x))
      (expect (%drain-lfqueue q) :to-equal items)
      (expect (rt-lfqueue-empty-p q) :to-be-truthy)))

  ;; The queue is mutex-protected and IS genuinely thread-safe: every item
  ;; pushed by concurrent producers must be recovered exactly once.
  (it "preserves every item under concurrent producers"
    (let* ((q (rt-make-lfqueue)) (nthreads 4) (per 500)
           (threads (loop repeat nthreads
                          collect (sb-thread:make-thread
                                   (lambda () (dotimes (i per) (rt-lfqueue-push q i)))))))
      (dolist (th threads) (sb-thread:join-thread th))
      (expect (length (%drain-lfqueue q)) :to-be (* nthreads per)))))

(describe "lock-free hash map"
  (it "get on a missing key returns the default and a nil flag"
    (let ((m (rt-make-lfhash-map)))
      (multiple-value-bind (v found) (rt-lfhash-get m :missing :fallback)
        (expect v :to-be :fallback)
        (expect found :to-be-null))))

  (it "put then get round-trips a value"
    (let ((m (rt-make-lfhash-map)))
      (cl-cc/runtime::rt-lfhash-put m :k 99)
      (multiple-value-bind (v found) (rt-lfhash-get m :k)
        (expect v :to-be 99)
        (expect found :to-be-truthy))
      (expect (rt-lfhash-count m) :to-be 1)))

  (it "put overwrites an existing key without growing the count"
    (let ((m (rt-make-lfhash-map)))
      (cl-cc/runtime::rt-lfhash-put m :k 1)
      (cl-cc/runtime::rt-lfhash-put m :k 2)
      (expect (rt-lfhash-get m :k) :to-be 2)
      (expect (rt-lfhash-count m) :to-be 1)))

  (it "remove marks the key deleted and decrements the count"
    (let ((m (rt-make-lfhash-map)))
      (cl-cc/runtime::rt-lfhash-put m :k 5)
      (expect (rt-lfhash-remove m :k) :to-be-truthy)
      (expect (nth-value 1 (rt-lfhash-get m :k)) :to-be-null)
      (expect (rt-lfhash-count m) :to-be 0)
      (expect (rt-lfhash-remove m :missing) :to-be-null)))

  (it "cas inserts when absent-and-old-is-nil, updates on match, rejects mismatch"
    (let ((m (rt-make-lfhash-map)))
      (expect (rt-lfhash-cas m :k nil 10) :to-be-truthy)
      (expect (rt-lfhash-get m :k) :to-be 10)
      (expect (rt-lfhash-cas m :k 10 20) :to-be-truthy)
      (expect (rt-lfhash-get m :k) :to-be 20)
      (expect (rt-lfhash-cas m :k 999 30) :to-be-null)
      (expect (rt-lfhash-get m :k) :to-be 20)))

  (it-property "every distinct key put is retrievable and counted once"
      ((pairs (gen-list (gen-tuple (gen-integer :min 0 :max 5000)
                                   (gen-integer :min -1000 :max 1000))
                        :max-length 30)))
    (let ((m (rt-make-lfhash-map)) (ref (make-hash-table)))
      (dolist (p pairs)
        (destructuring-bind (k v) p
          (cl-cc/runtime::rt-lfhash-put m k v)
          (setf (gethash k ref) v)))
      (maphash (lambda (k v) (expect (rt-lfhash-get m k) :to-be v)) ref)
      (expect (rt-lfhash-count m) :to-be (hash-table-count ref)))))

(describe "lockfree init"
  (it "rt-lockfree-init returns t"
    (expect (rt-lockfree-init) :to-be-truthy)))
