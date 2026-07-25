;;;; run-tests.lisp -- the Lisp-level entry point for the test suite.
;;;;
;;;; Lives at the repository root, not under scripts/: flake.nix, `nix run
;;;; .#test` and a bare `sbcl --script run-tests.lisp` all name the same path,
;;;; so there is one way to run the suite.
;;;;
;;;; Dependencies are located through CL_SOURCE_REGISTRY, which the flake's
;;;; checks, apps.test and devShell all set from the pinned sibling inputs.
;;;; This replaced a set of bespoke CL_CC_RUNTIME_<NAME>_ROOT variables: those
;;;; had to be enumerated both here and in the flake, so adding a dependency
;;;; meant editing two files, and running the suite by hand meant exporting
;;;; five variables instead of one.

(require :asdf)

(defun script-directory ()
  (make-pathname :name nil
                 :type nil
                 :defaults (or *load-truename*
                               *compile-file-truename*
                               (error "Unable to determine the script location"))))

(defun configure-local-source-registry (root)
  "Register this checkout, then inherit CL_SOURCE_REGISTRY for the siblings."
  (asdf:initialize-source-registry
   `(:source-registry
     (:tree ,root)
     :inherit-configuration)))

(let ((root (script-directory)))
  (configure-local-source-registry root)
  ;; test-op reaches "cl-cc-runtime/test" through :in-order-to, and that
  ;; system's :perform signals an error when cl-weave reports a failure, so a
  ;; failing suite exits non-zero without any status handling here.
  (asdf:test-system "cl-cc-runtime")
  (uiop:quit 0))
