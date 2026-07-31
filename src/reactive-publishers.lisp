;;;; reactive-publishers.lisp — Concrete Reactive Streams publishers
;;;; (list/map/filter/merge/zip) implementing the reactive.lisp protocol
(in-package :cl-cc/runtime)

(defstruct rt-list-publisher
  "Cold publisher that emits ITEMS in order as demand is requested."
  (items nil :type list))

(defstruct rt-map-publisher
  "Publisher that transforms each upstream item with FN."
  publisher
  (fn #'identity :type function))

(defstruct rt-filter-publisher
  "Publisher that emits only upstream items satisfying PRED."
  publisher
  (pred (lambda (item) (declare (ignore item)) t) :type function))

(defstruct rt-merge-publisher
  "Publisher that merges items from multiple PUBLISHERS under downstream demand."
  (publishers nil :type list))

(defstruct rt-zip-publisher
  "Publisher that pairs items from A and B and combines them with FN."
  a
  b
  (fn #'list :type function))

(defun rt-publisher-from-list (items)
  "Create a cold publisher that emits ITEMS in list order with backpressure."
  (make-rt-list-publisher :items (copy-list items)))

(defun rt-publisher-map (publisher fn)
  "Create a publisher that applies FN to every item from PUBLISHER."
  (make-rt-map-publisher :publisher publisher :fn fn))

(defun rt-publisher-filter (publisher pred)
  "Create a publisher that emits only items from PUBLISHER satisfying PRED."
  (make-rt-filter-publisher :publisher publisher :pred pred))

(defun rt-publisher-merge (&rest publishers)
  "Create a publisher that merges all PUBLISHERS into a single stream."
  (make-rt-merge-publisher :publishers publishers))

(defun rt-publisher-zip (a b &key (fn #'list))
  "Create a publisher that zips items from publishers A and B using FN.

FN is called with one item from A and one item from B for every downstream
request. Completion occurs when either upstream completes and no complete pair
can be formed."
  (make-rt-zip-publisher :a a :b b :fn fn))

(defmethod rt-subscribe ((publisher rt-list-publisher) subscriber)
  "Subscribe SUBSCRIBER to list PUBLISHER with pull-based delivery."
  (let ((remaining (copy-list (rt-list-publisher-items publisher)))
        (done nil)
        (cancelled nil))
    (labels ((complete-if-empty ()
               (when (and (not done) (not cancelled) (null remaining))
                 (setf done t)
                 (rt-on-complete subscriber)))
             (request (n)
               (cond
                 ((or done cancelled) nil)
                 ((not (%rt-positive-demand-p n))
                  (setf cancelled t done t)
                  (rt-on-error subscriber (%rt-demand-error n)))
                 (t
                  (loop while (and (> n 0) remaining (not done) (not cancelled))
                        for item = (pop remaining)
                        do (handler-case
                               (progn
                                 (rt-on-next subscriber item)
                                 (decf n))
                             (error (condition)
                               (setf cancelled t done t)
                               (rt-on-error subscriber condition))))
                  (complete-if-empty))))
             (cancel ()
               (setf cancelled t)
               t))
      (rt-on-subscribe subscriber
                       (make-rt-subscription :request-fn #'request :cancel-fn #'cancel)))))

(defmethod rt-subscribe ((publisher rt-map-publisher) subscriber)
  "Subscribe SUBSCRIBER to map PUBLISHER."
  (let ((upstream nil)
        (done nil))
    (labels ((cancel-upstream ()
               (when upstream (rt-cancel upstream)))
             (fail (error)
               (unless done
                 (setf done t)
                 (cancel-upstream)
                 (rt-on-error subscriber error))))
      (rt-subscribe
       (rt-map-publisher-publisher publisher)
       (rt-make-subscriber
        :on-subscribe (lambda (subscription)
                        (setf upstream subscription)
                        (rt-on-subscribe
                         subscriber
                         (make-rt-subscription
                          :request-fn (lambda (n)
                                        (if (%rt-positive-demand-p n)
                                            (rt-request subscription n)
                                            (fail (%rt-demand-error n))))
                          :cancel-fn (lambda ()
                                       (setf done t)
                                       (rt-cancel subscription)))))
        :on-next (lambda (item)
                   (unless done
                     (handler-case
                         (rt-on-next subscriber (funcall (rt-map-publisher-fn publisher) item))
                       (error (condition) (fail condition)))))
        :on-error (lambda (error) (fail error))
        :on-complete (lambda ()
                       (unless done
                         (setf done t)
                         (rt-on-complete subscriber))))))))

(defmethod rt-subscribe ((publisher rt-filter-publisher) subscriber)
  "Subscribe SUBSCRIBER to filter PUBLISHER."
  (let ((upstream nil)
        (done nil)
        (downstream-demand 0))
    (labels ((cancel-upstream ()
               (when upstream (rt-cancel upstream)))
             (fail (error)
               (unless done
                 (setf done t)
                 (cancel-upstream)
                 (rt-on-error subscriber error)))
             (request-upstream (n)
               (when (and upstream (not done))
                 (rt-request upstream n))))
      (rt-subscribe
       (rt-filter-publisher-publisher publisher)
       (rt-make-subscriber
        :on-subscribe (lambda (subscription)
                        (setf upstream subscription)
                        (rt-on-subscribe
                         subscriber
                         (make-rt-subscription
                          :request-fn (lambda (n)
                                        (cond
                                          ((not (%rt-positive-demand-p n))
                                           (fail (%rt-demand-error n)))
                                          ((not done)
                                           (incf downstream-demand n)
                                           (request-upstream n))))
                          :cancel-fn (lambda ()
                                       (setf done t)
                                       (rt-cancel subscription)))))
        :on-next (lambda (item)
                   (unless done
                     (handler-case
                         (if (funcall (rt-filter-publisher-pred publisher) item)
                             (when (> downstream-demand 0)
                               (decf downstream-demand)
                               (rt-on-next subscriber item))
                             (when (> downstream-demand 0)
                               (request-upstream 1)))
                       (error (condition) (fail condition)))))
        :on-error (lambda (error) (fail error))
        :on-complete (lambda ()
                       (unless done
                         (setf done t)
                         (rt-on-complete subscriber))))))))

(defmethod rt-subscribe ((publisher rt-merge-publisher) subscriber)
  "Subscribe SUBSCRIBER to merge PUBLISHER."
  (let* ((publishers (rt-merge-publisher-publishers publisher))
         (count (length publishers))
         (subscriptions nil)
         (completed 0)
         (next-index 0)
         (done nil))
    (labels ((cancel-all ()
               (dolist (subscription subscriptions) (rt-cancel subscription)))
             (fail (error)
               (unless done
                 (setf done t)
                 (cancel-all)
                 (rt-on-error subscriber error)))
             (request-one (subscription)
               (when (and subscription (not done))
                 (rt-request subscription 1)))
             (request-many (n)
               (cond
                 ((not (%rt-positive-demand-p n))
                  (fail (%rt-demand-error n)))
                 ((and subscriptions (not done))
                  (loop repeat n
                        for subscription = (nth (mod next-index count) subscriptions)
                        do (incf next-index)
                           (request-one subscription))))))
      (if (null publishers)
          (rt-on-subscribe subscriber
                           (make-rt-subscription
                            :request-fn (lambda (n)
                                          (declare (ignore n))
                                          (unless done
                                            (setf done t)
                                            (rt-on-complete subscriber)))
                            :cancel-fn (lambda () (setf done t) t)))
          (progn
            (dolist (source publishers)
              (rt-subscribe
               source
               (rt-make-subscriber
                :on-subscribe (lambda (subscription)
                                (setf subscriptions (append subscriptions (list subscription))))
                :on-next (lambda (item)
                           (unless done
                             (handler-case
                                 (rt-on-next subscriber item)
                               (error (condition) (fail condition)))))
                :on-error (lambda (error) (fail error))
                :on-complete (lambda ()
                               (unless done
                                 (incf completed)
                                 (when (= completed count)
                                   (setf done t)
                                   (rt-on-complete subscriber)))))))
            (rt-on-subscribe subscriber
                             (make-rt-subscription
                              :request-fn #'request-many
                              :cancel-fn (lambda ()
                                           (setf done t)
                                           (cancel-all)))))))))

(defmethod rt-subscribe ((publisher rt-zip-publisher) subscriber)
  "Subscribe SUBSCRIBER to zip PUBLISHER."
  (let ((sub-a nil)
        (sub-b nil)
        (queue-a nil)
        (queue-b nil)
        (completed-a nil)
        (completed-b nil)
        (demand 0)
        (done nil))
    (labels ((cancel-all ()
               (when sub-a (rt-cancel sub-a))
               (when sub-b (rt-cancel sub-b)))
             (fail (error)
               (unless done
                 (setf done t)
                 (cancel-all)
                 (rt-on-error subscriber error)))
             (maybe-complete ()
               (when (and (not done)
                          (or (and completed-a (null queue-a))
                              (and completed-b (null queue-b))))
                 (setf done t)
                 (cancel-all)
                 (rt-on-complete subscriber)))
             (emit ()
               (loop while (and (not done) (> demand 0) queue-a queue-b)
                     for a = (pop queue-a)
                     for b = (pop queue-b)
                     do (decf demand)
                        (handler-case
                            (rt-on-next subscriber (funcall (rt-zip-publisher-fn publisher) a b))
                          (error (condition) (fail condition))))
               (maybe-complete))
             (request-pair (n)
               (cond
                 ((not (%rt-positive-demand-p n))
                  (fail (%rt-demand-error n)))
                 ((not done)
                  (incf demand n)
                  (when sub-a (rt-request sub-a n))
                  (when sub-b (rt-request sub-b n))
                  (emit)))))
      (rt-subscribe
       (rt-zip-publisher-a publisher)
       (rt-make-subscriber
        :on-subscribe (lambda (subscription) (setf sub-a subscription))
        :on-next (lambda (item)
                   (unless done
                     (setf queue-a (append queue-a (list item)))
                     (emit)))
        :on-error (lambda (error) (fail error))
        :on-complete (lambda ()
                       (setf completed-a t)
                       (maybe-complete))))
      (rt-subscribe
       (rt-zip-publisher-b publisher)
       (rt-make-subscriber
        :on-subscribe (lambda (subscription) (setf sub-b subscription))
        :on-next (lambda (item)
                   (unless done
                     (setf queue-b (append queue-b (list item)))
                     (emit)))
        :on-error (lambda (error) (fail error))
        :on-complete (lambda ()
                       (setf completed-b t)
                       (maybe-complete))))
      (rt-on-subscribe subscriber
                       (make-rt-subscription
                        :request-fn #'request-pair
                        :cancel-fn (lambda ()
                                     (setf done t)
                                     (cancel-all)))))))
