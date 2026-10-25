(in-package :cl-cc/runtime/conditions/test)

(it-sequential "rt-signal-error-signals"
  (signals error (cl-cc/runtime/conditions:rt-signal-error "test error")))

(it-sequential "rt-signal-conditions"
  (let ((%%signaled2 nil)) (handler-case (progn (cl-cc/runtime/conditions:rt-signal (make-condition 'simple-condition :format-control "test"))) (simple-condition () (setf %%signaled2 t))) (expect %%signaled2 :to-be-truthy))
  (let ((%%signaled3 nil)) (handler-case (progn (cl-cc/runtime/conditions:rt-warn-fn "a warning")) (warning () (setf %%signaled3 t))) (expect %%signaled3 :to-be-truthy)))
