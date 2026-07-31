(in-package :cl-cc-runtime/test)

;;;; Tests for src/reactive.lisp — Reactive Streams / backpressure (FR-410).
;;;;
;;;; These assert the actual protocol semantics: a subscriber never receives more
;;;; items than it requested (backpressure), on-complete fires exactly once,
;;;; invalid demand terminates via on-error, and the map/filter/merge/zip
;;;; operators preserve those guarantees. The list publisher is a synchronous
;;;; cold source, so request() delivers inline and assertions can run eagerly.
;;; ── List publisher + backpressure ─────────────────────────────────
(it-sequential
  "A request of N delivers at most N items and does not complete early."
  (let ((received nil)
        (completed nil)
        (sub nil))
    (rt-subscribe
      (rt-publisher-from-list '(:a :b :c :d))
      (rt-make-subscriber
        :on-subscribe
        (lambda (s)
          (setf sub s))
        :on-next
        (lambda (x)
          (push x received))
        :on-complete
        (lambda ()
          (setf completed t))))
    (rt-request sub 2)
    (expect (reverse received) :to-equal '(:a :b))
    (expect completed :to-be-falsy)
    (rt-request sub 10)
    (expect (reverse received) :to-equal '(:a :b :c :d))
    (expect completed :to-be-truthy)))

(it-sequential
  "An empty publisher completes on the first request without emitting items."
  (let ((received nil)
        (completed nil)
        (sub nil))
    (rt-subscribe
      (rt-publisher-from-list '())
      (rt-make-subscriber
        :on-subscribe
        (lambda (s)
          (setf sub s))
        :on-next
        (lambda (x)
          (push x received))
        :on-complete
        (lambda ()
          (setf completed t))))
    (rt-request sub 1)
    (expect received :to-be-null)
    (expect completed :to-be-truthy)))

(it-sequential
  "on-complete is delivered exactly once even across extra requests."
  (let ((completes 0)
        (sub nil))
    (rt-subscribe
      (rt-publisher-from-list '(1 2))
      (rt-make-subscriber
        :on-subscribe
        (lambda (s)
          (setf sub s))
        :on-complete
        (lambda ()
          (incf completes))))
    (rt-request sub 5)
    (rt-request sub 5)
    (expect completes :to-equal 1)))

(it-sequential
  "Non-positive demand terminates the stream through on-error, not on-next."
  (let ((errored nil)
        (received nil)
        (sub nil))
    (rt-subscribe
      (rt-publisher-from-list '(1 2 3))
      (rt-make-subscriber
        :on-subscribe
        (lambda (s)
          (setf sub s))
        :on-next
        (lambda (x)
          (push x received))
        :on-error
        (lambda (e)
          (setf errored e))))
    (rt-request sub 0)
    (expect errored :to-be-truthy)
    (expect received :to-be-null)))

(cl-weave:it-property "list publisher never emits more than requested"
    ((n (cl-weave:gen-integer :min 1 :max 10))
     (len (cl-weave:gen-integer :min 0 :max 10)))
  (let ((items (loop for i below len collect i))
        (received nil)
        (sub nil))
    (rt-subscribe (rt-publisher-from-list items)
                  (rt-make-subscriber
                   :on-subscribe (lambda (s) (setf sub s))
                   :on-next (lambda (x) (push x received))))
    (rt-request sub n)
    ;; backpressure: received count is bounded by both demand and availability
    (cl-weave:expect (length received) :to-be (min n len))))

;;; ── Cancellation ──────────────────────────────────────────────────
(it-sequential
  "After cancel, further requests deliver no more items."
  (let ((received nil)
        (sub nil))
    (rt-subscribe
      (rt-publisher-from-list '(1 2 3 4))
      (rt-make-subscriber
        :on-subscribe
        (lambda (s)
          (setf sub s))
        :on-next
        (lambda (x)
          (push x received))))
    (rt-request sub 1)
    (rt-cancel sub)
    (rt-request sub 10)
    (expect (reverse received) :to-equal '(1))))

;;; ── collect ───────────────────────────────────────────────────────
(it-sequential
  "rt-subscriber-collect resolves its future to all emitted items in order."
  (let* ((sub
        (rt-make-subscriber
          :on-subscribe
          (lambda (s)
            (rt-request s 100))))
         (future (rt-subscriber-collect sub)))
    (rt-subscribe (rt-publisher-from-list '(10 20 30)) sub)
    (expect (cl-cc/runtime::rt-future-resolved-p future) :to-be-truthy)
    (expect (cl-cc/runtime::rt-future-value future) :to-equal '(10 20 30))))

;;; ── map ───────────────────────────────────────────────────────────
(it-sequential
  "map applies FN to each item, preserving order and backpressure."
  (let ((received nil)
        (sub nil))
    (rt-subscribe
      (rt-publisher-map (rt-publisher-from-list '(1 2 3)) #'1+)
      (rt-make-subscriber
        :on-subscribe
        (lambda (s)
          (setf sub s))
        :on-next
        (lambda (x)
          (push x received))))
    (rt-request sub 3)
    (expect (reverse received) :to-equal '(2 3 4))))

;;; ── filter ────────────────────────────────────────────────────────
(it-sequential
  "filter emits only items satisfying PRED, up to downstream demand."
  (let ((received nil)
        (sub nil))
    (rt-subscribe
      (rt-publisher-filter (rt-publisher-from-list '(1 2 3 4 5 6)) #'evenp)
      (rt-make-subscriber
        :on-subscribe
        (lambda (s)
          (setf sub s))
        :on-next
        (lambda (x)
          (push x received))))
    (rt-request sub 2)
    (expect (reverse received) :to-equal '(2 4))))

;;; ── merge ─────────────────────────────────────────────────────────
(it-sequential
  "merge emits every item from all sources and completes once all complete."
  (let ((received nil)
        (completed nil)
        (sub nil))
    (rt-subscribe
      (rt-publisher-merge
        (rt-publisher-from-list '(1 2))
        (rt-publisher-from-list '(10 20)))
      (rt-make-subscriber
        :on-subscribe
        (lambda (s)
          (setf sub s))
        :on-next
        (lambda (x)
          (push x received))
        :on-complete
        (lambda ()
          (setf completed t))))
    (rt-request sub 10)
    (expect (sort (copy-list received) #'<) :to-equal '(1 2 10 20))
    (expect completed :to-be-truthy)))

(it-sequential
  "Merging zero publishers completes on first request."
  (let ((completed nil)
        (sub nil))
    (rt-subscribe
      (rt-publisher-merge)
      (rt-make-subscriber
        :on-subscribe
        (lambda (s)
          (setf sub s))
        :on-complete
        (lambda ()
          (setf completed t))))
    (rt-request sub 1)
    (expect completed :to-be-truthy)))

;;; ── zip ───────────────────────────────────────────────────────────
(it-sequential
  "zip pairs items from A and B with FN and completes when one side ends."
  (let ((received nil)
        (completed nil)
        (sub nil))
    (rt-subscribe
      (rt-publisher-zip
        (rt-publisher-from-list '(1 2 3))
        (rt-publisher-from-list '(:a :b :c)))
      (rt-make-subscriber
        :on-subscribe
        (lambda (s)
          (setf sub s))
        :on-next
        (lambda (x)
          (push x received))
        :on-complete
        (lambda ()
          (setf completed t))))
    (rt-request sub 3)
    (expect (reverse received) :to-equal '((1 :a) (2 :b) (3 :c)))
    (expect completed :to-be-truthy)))

(it-sequential
  "zip uses a supplied combining function."
  (let ((received nil)
        (sub nil))
    (rt-subscribe
      (rt-publisher-zip
        (rt-publisher-from-list '(1 2))
        (rt-publisher-from-list '(10 20))
        :fn
        #'+)
      (rt-make-subscriber
        :on-subscribe
        (lambda (s)
          (setf sub s))
        :on-next
        (lambda (x)
          (push x received))))
    (rt-request sub 2)
    (expect (reverse received) :to-equal '(11 22))))
