(in-package :cl-cc/runtime/conditions/test)

(it-sequential "FR-300: Runtime handler and restart stacks establish dynamic recovery frames." (let ((handled nil))
    (multiple-value-bind (value foundp)
        (cl-cc/runtime::rt-establish-handler
         'error
         (lambda (condition) (setf handled condition) :handled)
         (lambda () (cl-cc/runtime::rt-dispatch-signal
                     (make-condition 'simple-error :format-control "x"))))
      (expect foundp :to-be-truthy)
      (expect value :to-be :handled)
      (expect (typep handled 'simple-error) :to-be-truthy)))
  (multiple-value-bind (value foundp)
      (cl-cc/runtime::rt-establish-restart
       'use-value
       (lambda (x) x)
       (lambda () (cl-cc/runtime::rt-dispatch-restart 'use-value '(42))))
    (expect foundp :to-be-truthy)
    (expect value :to-equal 42)))
