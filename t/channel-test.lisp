;;;; t/channel-test.lisp
;;;;
;;;; Tests for src/channel.lisp — CSP-style channels with an optional bounded
;;;; buffer, real mutex/condition-variable blocking, close semantics, and a
;;;; polling select.  The buffer is FIFO (enqueue appends, dequeue pops the
;;;; head).  Blocking send/recv are exercised with genuine producer/consumer
;;;; OS threads; ordering invariants are checked with property-based tests.

(in-package :cl-cc-runtime/test)

(in-suite cl-cc-unit-suite)

;;; ─── Construction & predicates ──────────────────────────────────────────────

(deftest channel-make-defaults-unbuffered-open
  "A freshly made channel is open, empty, and (capacity 0) unbuffered."
  (let ((ch (cl-cc/runtime::rt-make-channel)))
    (assert-true (cl-cc/runtime::rt-channel-open-p ch))
    (assert-false (cl-cc/runtime::rt-channel-buffered-p ch))
    (assert-= 0 (cl-cc/runtime::rt-channel-count ch))))

(deftest channel-make-buffered-reports-capacity
  "A positive capacity makes the channel buffered."
  (let ((ch (cl-cc/runtime::rt-make-channel :capacity 3)))
    (assert-true (cl-cc/runtime::rt-channel-buffered-p ch))))

(deftest channel-negative-capacity-clamped-to-zero
  "rt-make-channel clamps a negative capacity to 0."
  (let ((ch (cl-cc/runtime::rt-make-channel :capacity -5)))
    (assert-= 0 (cl-cc/runtime::rt-channel-capacity ch))))

;;; ─── Non-blocking try-send / try-recv on a buffered channel ─────────────────

(deftest channel-buffered-try-send-until-full
  "try-send succeeds up to capacity, then fails; count tracks the buffer."
  (let ((ch (cl-cc/runtime::rt-make-channel :capacity 2)))
    (assert-true (cl-cc/runtime::rt-channel-try-send ch :a))
    (assert-true (cl-cc/runtime::rt-channel-try-send ch :b))
    (assert-= 2 (cl-cc/runtime::rt-channel-count ch))
    (assert-false (cl-cc/runtime::rt-channel-try-send ch :c))))

(deftest channel-try-recv-is-fifo
  "try-recv returns buffered values in first-in-first-out order."
  (let ((ch (cl-cc/runtime::rt-make-channel :capacity 3)))
    (cl-cc/runtime::rt-channel-try-send ch 1)
    (cl-cc/runtime::rt-channel-try-send ch 2)
    (cl-cc/runtime::rt-channel-try-send ch 3)
    (assert-= 1 (cl-cc/runtime::rt-channel-try-recv ch))
    (assert-= 2 (cl-cc/runtime::rt-channel-try-recv ch))
    (assert-= 3 (cl-cc/runtime::rt-channel-try-recv ch))))

(deftest channel-try-recv-empty-returns-nil
  "try-recv on an empty channel returns NIL (no second value)."
  (let ((ch (cl-cc/runtime::rt-make-channel :capacity 1)))
    (multiple-value-bind (val ok) (cl-cc/runtime::rt-channel-try-recv ch)
      (assert-null val)
      (assert-null ok))))

;;; ─── send / recv without blocking (buffered) ────────────────────────────────

(deftest channel-send-recv-roundtrip
  "rt-channel-send then rt-channel-recv returns the value with a true 2nd value."
  (let ((ch (cl-cc/runtime::rt-make-channel :capacity 1)))
    (cl-cc/runtime::rt-channel-send ch :hello)
    (multiple-value-bind (val ok) (cl-cc/runtime::rt-channel-recv ch)
      (assert-eq :hello val)
      (assert-true ok))))

;;; ─── Close semantics ────────────────────────────────────────────────────────

(deftest channel-close-marks-closed
  "rt-channel-close closes the channel; open-p becomes false."
  (let ((ch (cl-cc/runtime::rt-make-channel :capacity 1)))
    (assert-true (cl-cc/runtime::rt-channel-close ch))
    (assert-false (cl-cc/runtime::rt-channel-open-p ch))))

(deftest channel-send-on-closed-errors
  "Sending to a closed channel signals an error."
  (let ((ch (cl-cc/runtime::rt-make-channel :capacity 1)))
    (cl-cc/runtime::rt-channel-close ch)
    (assert-signals error (cl-cc/runtime::rt-channel-send ch :x))))

(deftest channel-recv-closed-empty-returns-nil-nil
  "Receiving from a closed, drained channel returns (values nil nil)."
  (let ((ch (cl-cc/runtime::rt-make-channel :capacity 1)))
    (cl-cc/runtime::rt-channel-close ch)
    (multiple-value-bind (val ok) (cl-cc/runtime::rt-channel-recv ch)
      (assert-null val)
      (assert-null ok))))

(deftest channel-recv-drains-buffer-after-close
  "A closed channel still yields already-buffered values before reporting empty."
  (let ((ch (cl-cc/runtime::rt-make-channel :capacity 2)))
    (cl-cc/runtime::rt-channel-try-send ch :buffered)
    (cl-cc/runtime::rt-channel-close ch)
    (multiple-value-bind (val ok) (cl-cc/runtime::rt-channel-recv ch)
      (assert-eq :buffered val)
      (assert-true ok))
    ;; Now empty and closed.
    (multiple-value-bind (val ok) (cl-cc/runtime::rt-channel-recv ch)
      (assert-null val) (assert-null ok))))

;;; ─── select ─────────────────────────────────────────────────────────────────

(deftest channel-select-returns-first-ready
  "rt-channel-select returns a value from a ready channel with its channel."
  (let ((c1 (cl-cc/runtime::rt-make-channel :capacity 1))
        (c2 (cl-cc/runtime::rt-make-channel :capacity 1)))
    (cl-cc/runtime::rt-channel-try-send c2 :from-c2)
    (multiple-value-bind (val ch ok) (cl-cc/runtime::rt-channel-select (list c1 c2))
      (assert-eq :from-c2 val)
      (assert-eq c2 ch)
      (assert-true ok))))

(deftest channel-select-default-when-none-ready
  "With no ready channel and a :default, select returns the default and NILs."
  (let ((c1 (cl-cc/runtime::rt-make-channel :capacity 1)))
    (multiple-value-bind (val ch ok)
        (cl-cc/runtime::rt-channel-select (list c1) :default :nada)
      (assert-eq :nada val)
      (assert-null ch)
      (assert-null ok))))

(deftest channel-select-timeout-returns-nils
  "select with a timeout and no ready channel returns all NILs after expiry."
  (let ((c1 (cl-cc/runtime::rt-make-channel :capacity 1)))
    (multiple-value-bind (val ch ok)
        (cl-cc/runtime::rt-channel-select (list c1) :timeout 0.02)
      (assert-null val) (assert-null ch) (assert-null ok))))

;;; ─── Genuine producer/consumer concurrency ──────────────────────────────────

(deftest channel-blocking-producer-consumer
  "A capacity-1 channel forces the producer to block until the consumer drains;
all items arrive in FIFO order across two real OS threads."
  (let* ((ch (cl-cc/runtime::rt-make-channel :capacity 1))
         (n 20)
         (received (make-array n :fill-pointer 0))
         (consumer (sb-thread:make-thread
                    (lambda ()
                      (dotimes (i n)
                        (vector-push (cl-cc/runtime::rt-channel-recv ch) received)))
                    :name "chan-consumer"))
         (producer (sb-thread:make-thread
                    (lambda ()
                      (dotimes (i n)
                        (cl-cc/runtime::rt-channel-send ch i)))
                    :name "chan-producer")))
    (sb-thread:join-thread producer)
    (sb-thread:join-thread consumer)
    (assert-equal (loop for i below n collect i)
                  (coerce received 'list))))

;;; ─── Property: buffered channel preserves FIFO order ─────────────────────────

(cl-weave:it-property "buffered channel drains in the order values were sent"
    ((values (cl-weave:gen-list (cl-weave:gen-integer :min 0 :max 100)
                                :min-length 0 :max-length 12)))
  (let ((ch (cl-cc/runtime::rt-make-channel :capacity (max 1 (length values)))))
    (dolist (v values) (cl-cc/runtime::rt-channel-try-send ch v))
    (equal values
           (loop repeat (length values)
                 collect (cl-cc/runtime::rt-channel-try-recv ch)))))
