;;;; tests/package.lisp — cl-cc-runtime test package + cl-weave compatibility shim.
;;;;
;;;; Re-expresses the monorepo deftest / deftest-each / assert-* forms on top of
;;;; cl-weave's it-sequential / expect, so the suite runs on cl-weave with only
;;;; an in-package change per file.

(defpackage :cl-cc-runtime/test
  (:use :cl :cl-weave :cl-cc/runtime)
  (:shadowing-import-from :cl-weave #:describe)
  (:export #:deftest #:deftest-each #:in-suite #:defsuite #:defbefore
           #:assert-true #:assert-false #:assert-eq #:assert-eql
           #:assert-= #:assert-equal #:assert-equalp #:assert-null
           #:assert-string= #:assert-type #:assert-signals))

(in-package :cl-cc-runtime/test)

(defun %test-name (designator)
  (if (stringp designator) designator (string-downcase (string designator))))

(defmacro deftest (name &body body)
  (when (and (stringp (first body)) (rest body))
    (setf body (rest body)))
  `(it-sequential ,(%test-name name) ,@body))

(defmacro deftest-each (base-name &body args)
  (when (stringp (first args))
    (setf args (rest args)))
  (let* ((cases-pos (position :cases args))
         (cases (nth (1+ cases-pos) args))
         (tail  (nthcdr (+ 2 cases-pos) args))
         (vars  (first tail))
         (body  (rest tail)))
    `(progn
       ,@(loop for case in cases
               for label = (first case)
               for vals  = (rest case)
               collect `(it-sequential ,(format nil "~A ~A" (%test-name base-name) label)
                          (destructuring-bind ,vars (list ,@vals)
                            (declare (ignorable ,@vars))
                            ,@body))))))

(defmacro in-suite (&rest ignored) (declare (ignore ignored)) nil)
(defmacro defsuite (name &rest options) (declare (ignore name options)) nil)

(defmacro defbefore (kind suites &body body)
  (declare (ignore suites))
  (ecase kind
    (:each `(before-each ,@body))
    (:all  `(before-all ,@body))))

(defmacro assert-true (form &rest _)       (declare (ignore _)) `(expect ,form :to-be-truthy))
(defmacro assert-false (form &rest _)      (declare (ignore _)) `(expect ,form :to-be-falsy))
(defmacro assert-null (form &rest _)       (declare (ignore _)) `(expect ,form :to-be-null))
(defmacro assert-eq (expected actual &rest _)     (declare (ignore _)) `(expect ,actual :to-be ,expected))
(defmacro assert-eql (expected actual &rest _)    (declare (ignore _)) `(expect ,actual :to-be ,expected))
(defmacro assert-= (expected actual &rest _)      (declare (ignore _)) `(expect ,actual :to-equal ,expected))
(defmacro assert-equal (expected actual &rest _)  (declare (ignore _)) `(expect ,actual :to-equal ,expected))
(defmacro assert-equalp (expected actual &rest _) (declare (ignore _)) `(expect ,actual :to-equalp ,expected))
(defmacro assert-string= (expected actual &rest _) (declare (ignore _)) `(expect ,actual :to-equal ,expected))

(defmacro assert-type (type-name object &rest _)
  (declare (ignore _))
  `(expect (typep ,object ',type-name) :to-be-truthy))

(defmacro assert-signals (condition &body body)
  (let ((flag (gensym "SIGNALED")))
    `(let ((,flag nil))
       (handler-case (progn ,@body)
         (,condition () (setf ,flag t)))
       (expect ,flag :to-be-truthy))))
