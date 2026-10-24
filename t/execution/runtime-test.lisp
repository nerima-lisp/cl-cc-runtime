(in-package :cl-cc/runtime/execution/test)

(it-sequential
  "rt-make-closure returns an rt-closure-obj."
  (let ((c (cl-cc/runtime::rt-make-closure #'identity '(1 2 3))))
    (expect (cl-cc/runtime::rt-closure-obj-p c) :to-be-truthy)))

(it-sequential
  "rt-closure-ref retrieves captured values by index."
  (let ((c (cl-cc/runtime::rt-make-closure #'identity '(a b c))))
    (expect (cl-cc/runtime::rt-closure-ref c 0) :to-be 'a)
    (expect (cl-cc/runtime::rt-closure-ref c 1) :to-be 'b)
    (expect (cl-cc/runtime::rt-closure-ref c 2) :to-be 'c)))

(it-sequential-each (("closure" :closure-double (5) 10)
                      ("plain-fn" :plain-plus (3 4) 7))
    "rt-call-fn dispatches uniformly to closures and plain functions (~A)."
    (label kind args expected)
  (declare (ignore label))
  (let ((fn (ecase kind
              (:closure-double (cl-cc/runtime::rt-make-closure (lambda (x) (* x 2)) nil))
              (:plain-plus #'+))))
    (expect (apply #'cl-cc/runtime::rt-call-fn fn args) :to-equal expected)))

(it-sequential-each (("closure" :closure-add (10 5) 15)
                      ("plain-fn" :plain-times (2 3) 6))
    "rt-apply-fn applies args list uniformly to closures and plain functions (~A)."
    (label kind args expected)
  (declare (ignore label))
  (let ((fn (ecase kind
              (:closure-add (cl-cc/runtime::rt-make-closure (lambda (a b) (+ a b)) nil))
              (:plain-times #'*))))
    (expect (cl-cc/runtime::rt-apply-fn fn args) :to-equal expected)))
