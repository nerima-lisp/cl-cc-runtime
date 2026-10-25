(in-package :cl-cc/runtime/os/test)

(it-sequential "rt-write-to-string-roundtrip"
  (expect (cl-cc/runtime/os:rt-write-to-string '(1 2 3))
          :to-equal "(1 2 3)"))

(it-sequential "rt-universal-time-is-integer"
  (expect (integerp (cl-cc/runtime/os:rt-get-universal-time))
          :to-be-truthy))

(it-sequential "rt-string-stream-creation-and-io"
  (let ((s (cl-cc/runtime/os:rt-make-string-stream "hello")))
    (expect (cl-cc/runtime/os:rt-read-char s) :to-equal #\h))
  (let ((s (cl-cc/runtime/os:rt-make-string-stream "" :direction :output)))
    (cl-cc/runtime/os:rt-write-string "world" s)
    (expect (cl-cc/runtime/os:rt-get-output-stream-string s) :to-equal "world"))
  (let ((s (cl-cc/runtime/os:rt-make-string-output-stream)))
    (cl-cc/runtime/os:rt-stream-write-string s "test")
    (expect (cl-cc/runtime/os:rt-get-output-stream-string s) :to-equal "test")))

(it-sequential "rt-stream-predicates input-true"
  (destructuring-bind (pred-fn direction verify) (list #'cl-cc/runtime/os:rt-input-stream-p :input (lambda (pred-fn stream) (expect (= 1 (funcall pred-fn stream)) :to-be-truthy)))
    (let ((stream (ecase direction
                  (:input  (make-string-input-stream "x"))
                  (:output (make-string-output-stream)))))
    (funcall verify pred-fn stream))))

(it-sequential "rt-stream-predicates input-false"
  (destructuring-bind (pred-fn direction verify) (list #'cl-cc/runtime/os:rt-input-stream-p :output (lambda (pred-fn stream) (expect (= 0 (funcall pred-fn stream)) :to-be-truthy)))
    (let ((stream (ecase direction
                  (:input  (make-string-input-stream "x"))
                  (:output (make-string-output-stream)))))
    (funcall verify pred-fn stream))))

(it-sequential "rt-stream-predicates output-true"
  (destructuring-bind (pred-fn direction verify) (list #'cl-cc/runtime/os:rt-output-stream-p :output (lambda (pred-fn stream) (expect (= 1 (funcall pred-fn stream)) :to-be-truthy)))
    (let ((stream (ecase direction
                  (:input  (make-string-input-stream "x"))
                  (:output (make-string-output-stream)))))
    (funcall verify pred-fn stream))))

(it-sequential "rt-stream-predicates output-false"
  (destructuring-bind (pred-fn direction verify) (list #'cl-cc/runtime/os:rt-output-stream-p :input (lambda (pred-fn stream) (expect (= 0 (funcall pred-fn stream)) :to-be-truthy)))
    (let ((stream (ecase direction
                  (:input  (make-string-input-stream "x"))
                  (:output (make-string-output-stream)))))
    (funcall verify pred-fn stream))))

(it-sequential "rt-stream-predicates open-true"
  (destructuring-bind (pred-fn direction verify) (list #'cl-cc/runtime/os:rt-open-stream-p :input (lambda (pred-fn stream) (expect (= 1 (funcall pred-fn stream)) :to-be-truthy)))
    (let ((stream (ecase direction
                  (:input  (make-string-input-stream "x"))
                  (:output (make-string-output-stream)))))
    (funcall verify pred-fn stream))))

(it-sequential "rt-read-write-char-roundtrip"
  (let ((out (make-string-output-stream)))
    (cl-cc/runtime/os:rt-write-char #\Z out)
    (let ((in (make-string-input-stream (get-output-stream-string out))))
      (expect (cl-cc/runtime/os:rt-read-char in) :to-equal #\Z))))

(it-sequential "rt-package-layer-publishes-bootstrap-function-hooks"
  (expect (cl-cc/runtime/values:rt-find-package :cl-cc/bootstrap)
          :to-be-truthy)
  (expect (symbolp (cl-cc/runtime/values:rt-intern
                    "RT-PACKAGE-HOOK-TEST"
                    :cl-cc/bootstrap))
          :to-be-truthy)
  (let ((symbol (gensym "RT-PACKAGE-HOOK-VALUE-")))
    (cl-cc/runtime/dynamic-binding:rt-set-symbol-value symbol :installed)
    (expect (eq (cl-cc/runtime/dynamic-binding:rt-symbol-value symbol)
                :installed)
            :to-be-truthy)
    (cl-cc/runtime/dynamic-binding:rt-makunbound symbol)))
