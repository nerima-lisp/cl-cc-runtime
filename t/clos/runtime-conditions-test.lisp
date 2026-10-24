(in-package :cl-cc/runtime/clos/test)

(it-sequential
  "rt-call-next-method reuses the frame args by default and honours new args."
  (let ((cl-cc/runtime::*rt-method-context-stack*
        (list
          (list
            :next-thunk
            (lambda (args)
              (apply #'+ args))
            :args
            '(1 2 3)))))
    (expect (cl-cc/runtime::rt-next-method-p) :to-be-truthy)
    (expect (cl-cc/runtime::rt-call-next-method) :to-equal 6)
    (expect (cl-cc/runtime::rt-call-next-method 10 20) :to-equal 30)))

(it-sequential
  "With no context, rt-next-method-p is false and rt-call-next-method errors."
  (let ((cl-cc/runtime::*rt-method-context-stack* nil))
    (expect (cl-cc/runtime::rt-next-method-p) :to-be-falsy)
    (signals error (cl-cc/runtime::rt-call-next-method))))
