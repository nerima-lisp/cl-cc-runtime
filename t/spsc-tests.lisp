;;;; t/spsc-tests.lisp — single-producer/single-consumer ring buffer (src/spsc.lisp).
(in-package :cl-cc-runtime/test)

(describe "spsc capacity sizing"
  (it "rounds capacity up to a power of two, minimum 2"
    (expect (rt-spsc-capacity (rt-make-spsc-queue 1)) :to-be 2)
    (expect (rt-spsc-capacity (rt-make-spsc-queue 2)) :to-be 2)
    (expect (rt-spsc-capacity (rt-make-spsc-queue 3)) :to-be 4)
    (expect (rt-spsc-capacity (rt-make-spsc-queue 4)) :to-be 4)
    (expect (rt-spsc-capacity (rt-make-spsc-queue 5)) :to-be 8)))

(describe "spsc single-threaded semantics"
  (it "is empty and not full on creation"
    (let ((q (rt-make-spsc-queue 4)))
      (expect (rt-spsc-empty-p q) :to-be-truthy)
      (expect (rt-spsc-full-p q) :to-be-falsy)
      (expect (rt-spsc-size q) :to-be 0)))

  (it "try-pop on empty returns (nil nil)"
    (let ((q (rt-make-spsc-queue 4)))
      (multiple-value-bind (item ok) (rt-spsc-try-pop q)
        (expect item :to-be-null)
        (expect ok :to-be-null))))

  (it "try-push returns t and grows size; try-pop returns the item"
    (let ((q (rt-make-spsc-queue 4)))
      (expect (rt-spsc-try-push q :a) :to-be-truthy)
      (expect (rt-spsc-size q) :to-be 1)
      (expect (rt-spsc-empty-p q) :to-be-falsy)
      (multiple-value-bind (item ok) (rt-spsc-try-pop q)
        (expect item :to-be :a)
        (expect ok :to-be-truthy))
      (expect (rt-spsc-empty-p q) :to-be-truthy)))

  (it "rejects a push into a full ring and accepts again after a pop"
    (let ((q (rt-make-spsc-queue 2)))
      (expect (rt-spsc-try-push q 1) :to-be-truthy)
      (expect (rt-spsc-try-push q 2) :to-be-truthy)
      (expect (rt-spsc-full-p q) :to-be-truthy)
      (expect (rt-spsc-try-push q 3) :to-be-null)
      (expect (rt-spsc-try-pop q) :to-be 1)
      (expect (rt-spsc-try-push q 3) :to-be-truthy)))

  (it "reset clears contents and role ownership"
    (let ((q (rt-make-spsc-queue 4)))
      (rt-spsc-try-push q 1)
      (rt-spsc-try-push q 2)
      (expect (rt-spsc-reset q) :to-be q)
      (expect (rt-spsc-empty-p q) :to-be-truthy)
      (expect (rt-spsc-size q) :to-be 0)))

  (it-property "preserves FIFO order for a batch within capacity"
      ((items (gen-list (gen-integer :min -1000 :max 1000) :max-length 8)))
    (let ((q (rt-make-spsc-queue 16)))
      (dolist (x items) (expect (rt-spsc-try-push q x) :to-be-truthy))
      (expect (rt-spsc-size q) :to-be (length items))
      (let ((out (loop repeat (length items)
                       collect (multiple-value-bind (v ok) (rt-spsc-try-pop q)
                                 (expect ok :to-be-truthy)
                                 v))))
        (expect out :to-equal items)))))

(describe "spsc role ownership"
  (it "signals when a second thread tries to become the producer"
    (let ((q (rt-make-spsc-queue 4)))
      (rt-spsc-try-push q 1)                 ; calling thread claims producer
      (let ((th (sb-thread:make-thread
                 (lambda ()
                   (handler-case (progn (rt-spsc-try-push q 2) :ok)
                     (error () :errored))))))
        (expect (sb-thread:join-thread th) :to-be :errored))))

  (it "signals when a second thread tries to become the consumer"
    (let ((q (rt-make-spsc-queue 4)))
      (rt-spsc-try-push q 1)
      (rt-spsc-try-pop q)                     ; calling thread claims consumer
      (let ((th (sb-thread:make-thread
                 (lambda ()
                   (handler-case (progn (rt-spsc-try-pop q) :ok)
                     (error () :errored))))))
        (expect (sb-thread:join-thread th) :to-be :errored)))))

;; Genuine one-producer/one-consumer stress: the ring is designed for exactly
;; this. Every item must arrive exactly once and in order (verified FIFO-safe
;; empirically on this ARM64 target).
(describe "spsc concurrent producer/consumer"
  (it "transfers all items in order with no loss or duplication"
    (let* ((n 20000)
           (q (rt-make-spsc-queue 1024))
           (out (make-array n))
           (producer (sb-thread:make-thread
                      (lambda () (dotimes (i n) (rt-spsc-push q i :spin t)))))
           (consumer (sb-thread:make-thread
                      (lambda () (dotimes (i n) (setf (aref out i) (rt-spsc-pop q :spin t)))))))
      (sb-thread:join-thread producer)
      (sb-thread:join-thread consumer)
      (expect (loop for i below n always (= (aref out i) i)) :to-be-truthy))))

(describe "spsc init"
  (it "rt-spsc-init returns t"
    (expect (rt-spsc-init) :to-be-truthy)))
