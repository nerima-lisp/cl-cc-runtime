;;;; Reactive Streams / Backpressure (FR-410) — subscription/subscriber
;;;; protocol. Concrete publishers (list/map/filter/merge/zip) are in
;;;; reactive-publishers.lisp.
(in-package :cl-cc/runtime)

(defstruct rt-subscription
  "Reactive Streams subscription.

REQUEST-FN is called with a positive integer demand count. CANCEL-FN is called
when the downstream no longer wants items."
  (request-fn (lambda (n) (declare (ignore n)) nil) :type function)
  (cancel-fn (lambda () nil) :type function))

(defstruct rt-subscriber
  "Reactive Streams subscriber callback set.

ON-SUBSCRIBE receives an rt-subscription. ON-NEXT receives one item. ON-ERROR
receives a condition or error object. ON-COMPLETE is called exactly once after
normal completion."
  (on-subscribe (lambda (subscription) (declare (ignore subscription)) nil) :type function)
  (on-next (lambda (item) (declare (ignore item)) nil) :type function)
  (on-error (lambda (error) (declare (ignore error)) nil) :type function)
  (on-complete (lambda () nil) :type function))

(defgeneric rt-subscribe (publisher subscriber)
  (:documentation "Subscribe SUBSCRIBER to PUBLISHER and call rt-on-subscribe."))

(defgeneric rt-on-subscribe (subscriber subscription)
  (:documentation "Notify SUBSCRIBER that SUBSCRIPTION is ready for requests."))

(defgeneric rt-on-next (subscriber item)
  (:documentation "Deliver ITEM to SUBSCRIBER if it has not terminated."))

(defgeneric rt-on-error (subscriber error)
  (:documentation "Deliver ERROR to SUBSCRIBER and terminate the stream."))

(defgeneric rt-on-complete (subscriber)
  (:documentation "Notify SUBSCRIBER that the stream completed normally."))

(defmethod rt-on-subscribe ((subscriber rt-subscriber) subscription)
  "Invoke SUBSCRIBER's on-subscribe callback with SUBSCRIPTION."
  (funcall (rt-subscriber-on-subscribe subscriber) subscription))

(defmethod rt-on-next ((subscriber rt-subscriber) item)
  "Invoke SUBSCRIBER's on-next callback with ITEM."
  (funcall (rt-subscriber-on-next subscriber) item))

(defmethod rt-on-error ((subscriber rt-subscriber) error)
  "Invoke SUBSCRIBER's on-error callback with ERROR."
  (funcall (rt-subscriber-on-error subscriber) error))

(defmethod rt-on-complete ((subscriber rt-subscriber))
  "Invoke SUBSCRIBER's on-complete callback."
  (funcall (rt-subscriber-on-complete subscriber)))

(defun rt-request (subscription n)
  "Request N more items from SUBSCRIPTION's upstream publisher.

N must be a positive integer. Invalid demand signals an error through the
subscription request path."
  (funcall (rt-subscription-request-fn subscription) n))

(defun rt-cancel (subscription)
  "Cancel SUBSCRIPTION and stop future item delivery."
  (funcall (rt-subscription-cancel-fn subscription)))

(defun rt-make-subscriber (&key on-subscribe on-next on-error on-complete)
  "Create a simple callback-based subscriber.

ON-SUBSCRIBE, ON-NEXT, ON-ERROR, and ON-COMPLETE default to no-op callbacks."
  (make-rt-subscriber
   :on-subscribe (or on-subscribe (lambda (subscription) (declare (ignore subscription)) nil))
   :on-next (or on-next (lambda (item) (declare (ignore item)) nil))
   :on-error (or on-error (lambda (error) (declare (ignore error)) nil))
   :on-complete (or on-complete (lambda () nil))))

(defun %rt-positive-demand-p (n)
  "Return true when N is valid positive Reactive Streams demand."
  (and (integerp n) (> n 0)))

(defun %rt-demand-error (n)
  "Create a condition describing invalid demand N."
  (make-condition 'simple-error
                  :format-control "Reactive Streams request must be positive: ~s"
                  :format-arguments (list n)))

(defun rt-subscriber-collect (subscriber)
  "Collect SUBSCRIBER items into a list and return a future.

SUBSCRIBER is updated in place so its callbacks still run, while every item is
accumulated. The returned future resolves to the collected list on completion.
On error, the subscription is cancelled and the future resolves to the error
object after forwarding on-error."
  (let ((future (rt-make-future))
        (items nil)
        (subscription nil)
        (done nil)
        (old-on-subscribe (rt-subscriber-on-subscribe subscriber))
        (old-on-next (rt-subscriber-on-next subscriber))
        (old-on-error (rt-subscriber-on-error subscriber))
        (old-on-complete (rt-subscriber-on-complete subscriber)))
    (setf (rt-subscriber-on-subscribe subscriber)
          (lambda (sub)
            (setf subscription sub)
            (funcall old-on-subscribe sub))
          (rt-subscriber-on-next subscriber)
          (lambda (item)
            (unless done
              (setf items (append items (list item)))
              (funcall old-on-next item)))
          (rt-subscriber-on-error subscriber)
          (lambda (error)
            (unless done
              (setf done t)
              (when subscription (rt-cancel subscription))
              (funcall old-on-error error)
              (rt-future-resolve future error)))
          (rt-subscriber-on-complete subscriber)
          (lambda ()
            (unless done
              (setf done t)
              (funcall old-on-complete)
              (rt-future-resolve future items))))
    future))
