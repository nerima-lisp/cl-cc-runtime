(in-package :cl-cc/runtime/execution/test)

(it-sequential "rt-make-closure-creates-struct"
  (let ((c (cl-cc/runtime/execution:rt-make-closure #'identity '(1 2 3))))
    (expect (cl-cc/runtime/execution:rt-closure-obj-p c) :to-be-truthy)))

(it-sequential "rt-closure-ref-accesses-env"
  (let ((c (cl-cc/runtime/execution:rt-make-closure #'identity '(a b c))))
    (expect (cl-cc/runtime/execution:rt-closure-ref c 0) :to-be 'a)
    (expect (cl-cc/runtime/execution:rt-closure-ref c 1) :to-be 'b)
    (expect (cl-cc/runtime/execution:rt-closure-ref c 2) :to-be 'c)))

(it-sequential "rt-call-fn-dispatch closure"
  (destructuring-bind (fn args expected) (list (cl-cc/runtime/execution:rt-make-closure (lambda (x) (* x 2)) nil) '(5) 10)
    (expect (= expected (apply #'cl-cc/runtime/execution:rt-call-fn fn args)) :to-be-truthy)))

(it-sequential "rt-call-fn-dispatch plain-fn"
  (destructuring-bind (fn args expected) (list #'+ '(3 4) 7)
    (expect (= expected (apply #'cl-cc/runtime/execution:rt-call-fn fn args)) :to-be-truthy)))

(it-sequential "rt-apply-fn-dispatch closure"
  (destructuring-bind (fn args expected) (list (cl-cc/runtime/execution:rt-make-closure (lambda (a b) (+ a b)) nil) '(10 5) 15)
    (expect (= expected (cl-cc/runtime/execution:rt-apply-fn fn args)) :to-be-truthy)))

(it-sequential "rt-apply-fn-dispatch plain-fn"
  (destructuring-bind (fn args expected) (list #'* '(2 3) 6)
    (expect (= expected (cl-cc/runtime/execution:rt-apply-fn fn args)) :to-be-truthy)))

(it-sequential "rt-functionp-closure"
  (let ((c (cl-cc/runtime/execution:rt-make-closure #'identity nil)))
    (expect (= 1 (cl-cc/runtime/execution:rt-functionp c)) :to-be-truthy)))
