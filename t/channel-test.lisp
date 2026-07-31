;;;; t/channel-test.lisp
;;;;
;;;; Tests for src/channel.lisp — CSP-style channels with an optional bounded
;;;; buffer, real mutex/condition-variable blocking, close semantics, and a
;;;; polling select.  The buffer is FIFO (enqueue appends, dequeue pops the
;;;; head).  Blocking send/recv are exercised with genuine producer/consumer
;;;; OS threads; ordering invariants are checked with property-based tests.
(in-package :cl-cc-runtime/test)

;;; ─── Construction & predicates ──────────────────────────────────────────────
(it-sequential
  "A freshly made channel is open, empty, and (capacity 0) unbuffered."
  (let ((ch (cl-cc/runtime::rt-make-channel)))
    (expect (cl-cc/runtime::rt-channel-open-p ch) :to-be-truthy)
    (expect (cl-cc/runtime::rt-channel-buffered-p ch) :to-be-falsy)
    (expect (cl-cc/runtime::rt-channel-count ch) :to-equal 0)))

(it-sequential
  "A positive capacity makes the channel buffered."
  (let ((ch (cl-cc/runtime::rt-make-channel :capacity 3)))
    (expect (cl-cc/runtime::rt-channel-buffered-p ch) :to-be-truthy)))

(it-sequential
  "rt-make-channel clamps a negative capacity to 0."
  (let ((ch (cl-cc/runtime::rt-make-channel :capacity -5)))
    (expect (cl-cc/runtime::rt-channel-capacity ch) :to-equal 0)))

;;; ─── Non-blocking try-send / try-recv on a buffered channel ─────────────────
(it-sequential
  "try-send succeeds up to capacity, then fails; count tracks the buffer."
  (let ((ch (cl-cc/runtime::rt-make-channel :capacity 2)))
    (expect (cl-cc/runtime::rt-channel-try-send ch :a) :to-be-truthy)
    (expect (cl-cc/runtime::rt-channel-try-send ch :b) :to-be-truthy)
    (expect (cl-cc/runtime::rt-channel-count ch) :to-equal 2)
    (expect (cl-cc/runtime::rt-channel-try-send ch :c) :to-be-falsy)))

(it-sequential
  "try-recv returns buffered values in first-in-first-out order."
  (let ((ch (cl-cc/runtime::rt-make-channel :capacity 3)))
    (cl-cc/runtime::rt-channel-try-send ch 1)
    (cl-cc/runtime::rt-channel-try-send ch 2)
    (cl-cc/runtime::rt-channel-try-send ch 3)
    (expect (cl-cc/runtime::rt-channel-try-recv ch) :to-equal 1)
    (expect (cl-cc/runtime::rt-channel-try-recv ch) :to-equal 2)
    (expect (cl-cc/runtime::rt-channel-try-recv ch) :to-equal 3)))

(it-sequential
  "try-recv on an empty channel returns NIL (no second value)."
  (let ((ch (cl-cc/runtime::rt-make-channel :capacity 1)))
    (multiple-value-bind (val ok) (cl-cc/runtime::rt-channel-try-recv ch)
      (expect val :to-be-null)
      (expect ok :to-be-null))))

;;; ─── send / recv without blocking (buffered) ────────────────────────────────
(it-sequential
  "rt-channel-send then rt-channel-recv returns the value with a true 2nd value."
  (let ((ch (cl-cc/runtime::rt-make-channel :capacity 1)))
    (cl-cc/runtime::rt-channel-send ch :hello)
    (multiple-value-bind (val ok) (cl-cc/runtime::rt-channel-recv ch)
      (expect val :to-be :hello)
      (expect ok :to-be-truthy))))

;;; ─── Timeout ────────────────────────────────────────────────────────────────
;;; RT-CHANNEL-SEND/RT-CHANNEL-RECV used to re-pass the caller's original
;;; TIMEOUT to every RT-CONDITION-WAIT in their (possibly multi-phase) wait
;;; loops instead of sharing one shrinking deadline, so the effective wait
;;; could run for a multiple of TIMEOUT rather than TIMEOUT itself. These
;;; bound real elapsed time, not just the return value, so that regression
;;; stays fixed.
(it-sequential
  "rt-channel-send on a full buffered channel gives up at TIMEOUT rather than blocking forever"
  (let* ((ch (cl-cc/runtime::rt-make-channel :capacity 1))
         (started (get-internal-real-time)))
    (cl-cc/runtime::rt-channel-send ch :fills-the-only-slot)
    (multiple-value-bind (val ok) (cl-cc/runtime::rt-channel-send ch :never-fits :timeout 0.05)
      (expect val :to-be-null)
      (expect ok :to-be-null)
      (expect
        (< (- (get-internal-real-time) started) internal-time-units-per-second)
        :to-be-truthy))))
(it-sequential
  "rt-channel-recv on an empty channel gives up at TIMEOUT rather than blocking forever"
  (let* ((ch (cl-cc/runtime::rt-make-channel :capacity 1))
         (started (get-internal-real-time)))
    (multiple-value-bind (val ok) (cl-cc/runtime::rt-channel-recv ch :timeout 0.05)
      (expect val :to-be-null)
      (expect ok :to-be-null)
      (expect
        (< (- (get-internal-real-time) started) internal-time-units-per-second)
        :to-be-truthy))))

;;; ─── Close semantics ────────────────────────────────────────────────────────
(it-sequential
  "rt-channel-close closes the channel; open-p becomes false."
  (let ((ch (cl-cc/runtime::rt-make-channel :capacity 1)))
    (expect (cl-cc/runtime::rt-channel-close ch) :to-be-truthy)
    (expect (cl-cc/runtime::rt-channel-open-p ch) :to-be-falsy)))

(it-sequential
  "Sending to a closed channel signals an error."
  (let ((ch (cl-cc/runtime::rt-make-channel :capacity 1)))
    (cl-cc/runtime::rt-channel-close ch)
    (signals error (cl-cc/runtime::rt-channel-send ch :x))))

(it-sequential
  "Receiving from a closed, drained channel returns (values nil nil)."
  (let ((ch (cl-cc/runtime::rt-make-channel :capacity 1)))
    (cl-cc/runtime::rt-channel-close ch)
    (multiple-value-bind (val ok) (cl-cc/runtime::rt-channel-recv ch)
      (expect val :to-be-null)
      (expect ok :to-be-null))))

(it-sequential "A closed channel still yields already-buffered values before reporting empty." (let ((ch (cl-cc/runtime::rt-make-channel :capacity 2)))
    (cl-cc/runtime::rt-channel-try-send ch :buffered)
    (cl-cc/runtime::rt-channel-close ch)
    (multiple-value-bind (val ok) (cl-cc/runtime::rt-channel-recv ch)
      (expect val :to-be :buffered)
      (expect ok :to-be-truthy))
    ;; Now empty and closed.
    (multiple-value-bind (val ok) (cl-cc/runtime::rt-channel-recv ch)
      (expect val :to-be-null) (expect ok :to-be-null))))

;;; ─── select ─────────────────────────────────────────────────────────────────
(it-sequential
  "rt-channel-select returns a value from a ready channel with its channel."
  (let ((c1 (cl-cc/runtime::rt-make-channel :capacity 1))
        (c2 (cl-cc/runtime::rt-make-channel :capacity 1)))
    (cl-cc/runtime::rt-channel-try-send c2 :from-c2)
    (multiple-value-bind (val ch ok) (cl-cc/runtime::rt-channel-select (list c1 c2))
      (expect val :to-be :from-c2)
      (expect ch :to-be c2)
      (expect ok :to-be-truthy))))

(it-sequential
  "With no ready channel and a :default, select returns the default and NILs."
  (let ((c1 (cl-cc/runtime::rt-make-channel :capacity 1)))
    (multiple-value-bind (val ch ok) (cl-cc/runtime::rt-channel-select (list c1) :default :nada)
      (expect val :to-be :nada)
      (expect ch :to-be-null)
      (expect ok :to-be-null))))

(it-sequential
  "select with a timeout and no ready channel returns all NILs after expiry."
  (let ((c1 (cl-cc/runtime::rt-make-channel :capacity 1)))
    (multiple-value-bind (val ch ok) (cl-cc/runtime::rt-channel-select (list c1) :timeout 0.02)
      (expect val :to-be-null)
      (expect ch :to-be-null)
      (expect ok :to-be-null))))

;;; ─── Genuine producer/consumer concurrency ──────────────────────────────────
(it-sequential
  "A capacity-1 channel forces the producer to block until the consumer drains;
all items arrive in FIFO order across two real OS threads."
  (let* ((ch (cl-cc/runtime::rt-make-channel :capacity 1))
         (n 20)
         (received (make-array n :fill-pointer 0))
         (consumer
        (sb-thread:make-thread
          (lambda ()
            (dotimes (i n)
              (vector-push (cl-cc/runtime::rt-channel-recv ch) received)))
          :name
          "chan-consumer"))
         (producer
        (sb-thread:make-thread
          (lambda ()
            (dotimes (i n)
              (cl-cc/runtime::rt-channel-send ch i)))
          :name
          "chan-producer")))
    (sb-thread:join-thread producer)
    (sb-thread:join-thread consumer)
    (expect
      (coerce received 'list)
      :to-equal
      (loop for i below n
            collect i))))

;;; ─── Property: buffered channel preserves FIFO order ─────────────────────────

(cl-weave:it-property
  "buffered channel drains in the order values were sent"
  ((values
      (cl-weave:gen-list
        (cl-weave:gen-integer :min 0 :max 100)
        :min-length
        0
        :max-length
        12)))
  (let ((ch (cl-cc/runtime::rt-make-channel :capacity (max 1 (length values)))))
    (dolist (v values)
      (cl-cc/runtime::rt-channel-try-send ch v))
    (equal
      values
      (loop repeat (length values)
            collect (cl-cc/runtime::rt-channel-try-recv ch)))))

(it-sequential
  "A zero-capacity send completes only after a receiver accepts its value."
  (let* ((ch (cl-cc/runtime:rt-make-channel))
         (completed nil)
         (sender
        (sb-thread:make-thread
          (lambda ()
            (cl-cc/runtime:rt-channel-send ch :handoff)
            (setf completed t))
          :name
          "unbuffered-sender")))
    (sleep 0.02)
    (expect completed :to-be-null)
    (multiple-value-bind (value ok) (cl-cc/runtime:rt-channel-recv ch)
      (expect value :to-be :handoff)
      (expect ok :to-be-truthy))
    (sb-thread:join-thread sender)
    (expect completed :to-be-truthy)))

(it-sequential
  "Select registers as a receiver and commits exactly one competing handoff."
  (let* ((c1 (cl-cc/runtime:rt-make-channel))
         (c2 (cl-cc/runtime:rt-make-channel))
         (done1 nil)
         (done2 nil)
         (s1
        (sb-thread:make-thread
          (lambda ()
            (cl-cc/runtime:rt-channel-send c1 :one)
            (setf done1 t))
          :name
          "select-sender-1"))
         (s2
        (sb-thread:make-thread
          (lambda ()
            (cl-cc/runtime:rt-channel-send c2 :two)
            (setf done2 t))
          :name
          "select-sender-2")))
    (multiple-value-bind (value selected ok) (cl-cc/runtime:rt-channel-select (list c1 c2) :timeout 1.0)
      (expect ok :to-be-truthy)
      (expect
        (or
          (and (eq value :one) (eq selected c1))
          (and (eq value :two) (eq selected c2)))
        :to-be-truthy)
      (sleep 0.02)
      (expect (not (and done1 done2)) :to-be-truthy)
      (if (eq selected c1) (multiple-value-bind (remaining remaining-ok) (cl-cc/runtime:rt-channel-recv c2 :timeout 1.0)
          (expect remaining :to-be :two)
          (expect remaining-ok :to-be-truthy))
        (multiple-value-bind (remaining remaining-ok) (cl-cc/runtime:rt-channel-recv c1 :timeout 1.0)
          (expect remaining :to-be :one)
          (expect remaining-ok :to-be-truthy))))
    (sb-thread:join-thread s1)
    (sb-thread:join-thread s2)
    (expect done1 :to-be-truthy)
    (expect done2 :to-be-truthy)))

(it-sequential
  "A non-blocking zero-capacity send cannot buffer a value."
  (expect
    (cl-cc/runtime:rt-channel-try-send (cl-cc/runtime:rt-make-channel) :unreceived)
    :to-be-null))
