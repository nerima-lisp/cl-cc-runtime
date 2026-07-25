;;;; run-coverage.lisp -- instrument "cl-cc-runtime" with sb-cover, run the
;;;; cl-weave suite, and write an HTML report under coverage/.
;;;;
;;;; Not part of `nix flake check`: sb-cover needs to recompile every source
;;;; file with instrumentation, and the HTML report is an artifact to look at
;;;; rather than a pass/fail gate. Run it from `nix develop`, where
;;;; CL_SOURCE_REGISTRY already points at the pinned siblings.

(require :asdf)
(require :sb-cover)

(asdf:initialize-source-registry
 `(:source-registry
   (:tree ,(truename "."))
   :inherit-configuration))

(declaim (optimize sb-cover:store-coverage-data))
(handler-case (asdf:oos 'asdf:load-op "cl-cc-runtime" :force t)
  (error (e) (format t "~&FAIL load cl-cc-runtime: ~a~%" e) (finish-output) (sb-ext:exit :code 1)))

;; Only src/ is measured: instrumenting the test system would count the tests
;; as covered code and inflate the number.
(declaim (optimize (sb-cover:store-coverage-data 0)))
(handler-case (asdf:load-system "cl-cc-runtime/test")
  (error (e) (format t "~&FAIL load cl-cc-runtime/test: ~a~%" e) (finish-output) (sb-ext:exit :code 1)))

(funcall (find-symbol "RUN-ALL" :cl-weave) :reporter :spec :pass-with-no-tests nil)

(ensure-directories-exist "coverage/")
(sb-cover:report "coverage/")
(format t "~&Coverage report written to coverage/cover-index.html~%")
(finish-output)
