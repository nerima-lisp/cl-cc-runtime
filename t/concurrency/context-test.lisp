;;;; t/context-test.lisp — cancellation / deadline / value contexts (src/context.lisp).
(in-package :cl-cc/runtime/concurrency/test)

(describe
  "context deadlines (context.lisp)"
  (it
    "rt-with-context establishes the deadline reported by rt-context-get-deadline"
    (cl-cc/runtime/concurrency:rt-with-context
      (:deadline 12345)
      (expect (cl-cc/runtime/concurrency:rt-context-get-deadline) :to-be 12345)))
  (it
    "outside any context the deadline is nil"
    (let ((*rt-current-context* nil))
      (expect (cl-cc/runtime/concurrency:rt-context-get-deadline) :to-be-null)))
  (it
    "a context whose deadline is already in the past reports cancelled"
    (cl-cc/runtime/concurrency:rt-with-context
      (:deadline (- (get-internal-real-time) 1000))
      (expect (cl-cc/runtime/concurrency:rt-context-cancelled-p) :to-be-truthy)))
  (it
    "a context with a far-future deadline is not cancelled"
    (cl-cc/runtime/concurrency:rt-with-context
      (:deadline (+ (get-internal-real-time) (* 3600 internal-time-units-per-second)))
      (expect (cl-cc/runtime/concurrency:rt-context-cancelled-p) :to-be-null))))

(describe
  "context cancellation (context.lisp)"
  (it
    "an uncancelled context reports not-cancelled"
    (let ((ctx (make-rt-context)))
      (expect (cl-cc/runtime/concurrency:rt-context-cancelled-p ctx) :to-be-null)))
  (it
    "rt-context-cancel flips the cancelled flag"
    (let ((ctx (make-rt-context)))
      (cl-cc/runtime/concurrency:rt-context-cancel ctx)
      (expect (cl-cc/runtime/concurrency:rt-context-cancelled-p ctx) :to-be-truthy)))
  (it
    "cancellation propagates from a parent to its children"
    (let* ((parent (make-rt-context))
           (child (make-rt-context :parent parent)))
      (expect (cl-cc/runtime/concurrency:rt-context-cancelled-p child) :to-be-null)
      (cl-cc/runtime/concurrency:rt-context-cancel parent)
      (expect (cl-cc/runtime/concurrency:rt-context-cancelled-p child) :to-be-truthy)))
  (it
    "cancelling nil is a harmless no-op"
    (expect (cl-cc/runtime/concurrency:rt-context-cancel nil) :to-be-null)))

(describe
  "context values (context.lisp)"
  (it
    "set-value then value round-trips a binding"
    (let ((ctx (make-rt-context)))
      (rt-context-set-value :k 99 ctx)
      (expect (cl-cc/runtime/concurrency:rt-context-value :k ctx) :to-be 99)))
  (it
    "a child inherits values from its parent"
    (let* ((parent (make-rt-context))
           (child (make-rt-context :parent parent)))
      (rt-context-set-value :shared :from-parent parent)
      (expect (cl-cc/runtime/concurrency:rt-context-value :shared child) :to-be :from-parent)))
  (it
    "a child binding shadows the parent's binding"
    (let* ((parent (make-rt-context))
           (child (make-rt-context :parent parent)))
      (rt-context-set-value :k :parent parent)
      (rt-context-set-value :k :child child)
      (expect (cl-cc/runtime/concurrency:rt-context-value :k child) :to-be :child)
      (expect (cl-cc/runtime/concurrency:rt-context-value :k parent) :to-be :parent)))
  (it
    "an unbound key resolves to nil"
    (let ((ctx (make-rt-context)))
      (expect (cl-cc/runtime/concurrency:rt-context-value :missing ctx) :to-be-null)))
  (it
    "rt-context-copy duplicates deadline, cancelled flag, and values"
    (let ((ctx (make-rt-context :dl 500)))
      (rt-context-set-value :k 1 ctx)
      (cl-cc/runtime/concurrency:rt-context-cancel ctx)
      (let ((copy (rt-context-copy ctx)))
        (expect (rt-context-dl copy) :to-be 500)
        (expect (rt-context-cancelled copy) :to-be-truthy)
        (expect (cl-cc/runtime/concurrency:rt-context-value :k copy) :to-be 1))))
  (it
    "rt-context-copy of nil is nil"
    (expect (rt-context-copy nil) :to-be-null))
  (it
    "rt-with-context-value binds a value for the dynamic extent of the body"
    (let ((*rt-current-context* nil))
      (cl-cc/runtime/concurrency:rt-with-context-value
        (:token 42)
        (expect (cl-cc/runtime/concurrency:rt-context-value :token) :to-be 42)))))

(describe
  "rt-context-spawn propagation across the green-thread queue boundary (context.lisp)"
  (it-sequential
    "carries both the rt-context value and the cl-log-kit structured log context into the spawned thunk"
    (let* ((*rt-global-scheduler* (cl-cc/runtime/concurrency:rt-make-scheduler))
           (captured-records nil)
           (spawned-request-id nil)
           (logger (log-kit:make-logger
                     :name "context-spawn-test"
                     :handler (log-kit:make-function-handler
                               (lambda (record) (push record captured-records))))))
      (cl-cc/runtime/concurrency:rt-with-context ()
        (rt-context-set-value :request-id "abc123")
        (log-kit:with-log-context (:trace-id "trace-xyz")
          (cl-cc/runtime/concurrency:rt-context-spawn
            (lambda ()
              (setf spawned-request-id (cl-cc/runtime/concurrency:rt-context-value :request-id))
              (log-kit:log-info logger "inside spawned work")))))
      (cl-cc/runtime/concurrency:rt-scheduler-run)
      (expect spawned-request-id :to-equal "abc123")
      (expect
        (cdr (assoc :trace-id (log-kit:log-record-fields (first captured-records))))
        :to-equal
        "trace-xyz"))))
