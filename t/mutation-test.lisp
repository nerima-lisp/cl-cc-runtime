;;;; t/mutation-test.lisp
;;;;
;;;; Mutation testing: CL-WEAVE systematically mutates a pure function's body
;;;; (flipping arithmetic/comparison operators, boolean literals, and
;;;; conditional branches) and re-checks each variant against the same case
;;;; battery a unit test would use. A mutation the battery fails to notice
;;;; ("survived") marks a gap SB-COVER's line/branch coverage cannot see:
;;;; coverage proves a line executed, not that a wrong result there would be
;;;; caught. The body is read live from src/ on every run (never copied into
;;;; this file), so there is nothing here to fall out of sync with the real
;;;; implementation.

(in-package :cl-cc-runtime/test)

(defun %read-defun-forms (pathname)
  "Return every top-level DEFUN form read from PATHNAME.
Read with *PACKAGE* bound to CL-CC/RUNTIME so every symbol in the returned
forms -- the function name, parameters, and any CL-CC/RUNTIME function it
calls -- resolves to the same symbol the real, loaded definition uses."
  (let ((*package* (find-package "CL-CC/RUNTIME")))
    (with-open-file (stream pathname)
      (loop for form = (read stream nil :eof)
            until (eq form :eof)
            when (and (consp form) (eq (first form) 'cl:defun))
              collect form))))

(defun %find-defun-form (relative-path name)
  "Read RELATIVE-PATH's DEFUN named NAME, matching by symbol name (not
identity) since READ interns the file's symbols into *PACKAGE* at read time,
not the target file's own package."
  (let ((pathname (asdf:system-relative-pathname :cl-cc-runtime relative-path))
        (target-name (string name)))
    (or (find target-name (%read-defun-forms pathname)
              :key (lambda (form) (string (second form)))
              :test #'string=)
        (error "No DEFUN ~A found in ~A." name pathname))))

(defun %defun-lambda-list (defun-form)
  (third defun-form))

(defun %defun-body-form (defun-form)
  "Return DEFUN-FORM's body as a single form, skipping a leading docstring and
wrapping multiple body forms in a PROGN."
  (let ((body (cdddr defun-form)))
    (when (and (stringp (first body)) (rest body))
      (setf body (rest body)))
    (if (rest body) (cons 'cl:progn body) (first body))))

(defun %eval-with-bindings (form lambda-list argument-forms)
  (eval `(let ,(mapcar #'list lambda-list argument-forms) ,form)))

(defun %mutation-oracle (lambda-list cases)
  "Return a CL-WEAVE:RUN-MUTATIONS test function asserting MUTATED-FORM still
satisfies every (ARGUMENT-FORMS . EXPECTED) entry in CASES. A mismatch
signals ASSERTION-FAILURE via EXPECT, which RUN-MUTATIONS reports as a
killed mutation; matching every case leaves the mutation looking survived."
  (lambda (mutated-form mutation)
    (declare (ignore mutation))
    (dolist (case cases t)
      (destructuring-bind (argument-forms expected) case
        (expect (%eval-with-bindings mutated-form lambda-list argument-forms)
                :to-equal expected)))))

(defun %assert-full-mutation-kill (relative-path name cases)
  "Mutate the DEFUN named NAME in RELATIVE-PATH and assert CASES kills every
mutation (a mutation score of 1.0), i.e. the case battery is strong enough to
notice every one-operator change to the real implementation."
  (let* ((defun-form (%find-defun-form relative-path name))
         (lambda-list (%defun-lambda-list defun-form))
         (body (%defun-body-form defun-form))
         (results (run-mutations body (%mutation-oracle lambda-list cases))))
    (assert-mutation-score results 1.0)))

(defparameter +return-address-poisoned-p-cases+
  `(((:not-an-int) nil)
    ((0) nil)
    ((#x5afe000000000000) t)
    ((,(cl-cc/runtime::rt-poison-return-address 12345)) t)
    ((#x1234) nil))
  "Shared by both RT-RETURN-ADDRESS-POISONED-P tests below: the live-function
assertion and the mutation-kill assertion must agree on exactly the same
cases, or a case added to only one silently stops proving what its describe
block claims.")

(describe "src/runtime-stack.lisp: RT-RETURN-ADDRESS-POISONED-P mutation coverage"
  (it "the case battery matches the live function on every case"
    (with-soft-assertions
      (dolist (case +return-address-poisoned-p-cases+)
        (destructuring-bind (argument-forms expected) case
          (expect (cl-cc/runtime::rt-return-address-poisoned-p (first argument-forms))
                  :to-equal expected)))))
  (it "every mutation of RT-RETURN-ADDRESS-POISONED-P's body is killed by the case battery"
    (%assert-full-mutation-kill "src/runtime-stack.lisp" 'cl-cc/runtime::rt-return-address-poisoned-p
                                +return-address-poisoned-p-cases+)))
