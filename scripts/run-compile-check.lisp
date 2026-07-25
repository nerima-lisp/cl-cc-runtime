;;;; run-compile-check.lisp
;;;;
;;;; Compile and load "cl-cc-runtime" from the current source tree, then exit
;;;; non-zero on any compile or load error.
;;;;
;;;; This is no longer the CI gate: `packages.default` is a
;;;; `sbcl.buildASDFSystem` derivation, so `nix build` compiles the system, and
;;;; `checks.default` compiles it again on the way to running the suite. The
;;;; script is kept because a compile-only check is the fastest way to see
;;;; whether a change reads, and it is useful under `nix develop` where
;;;; CL_SOURCE_REGISTRY is already set to the pinned siblings.

(require :asdf)

;; Sibling systems (cl-log-kit, cl-process-kit and its own cl-boundary-kit
;; dependency, cl-json-kit) come from CL_SOURCE_REGISTRY, inherited below.
(asdf:initialize-source-registry
 `(:source-registry
   (:tree ,(truename "."))
   :inherit-configuration))

(handler-case
    (progn
      (asdf:load-system "cl-cc-runtime")
      (format t "~&PASS cl-cc-runtime compile check~%")
      (finish-output))
  (error (e)
    (format t "~&FAIL cl-cc-runtime: ~a~%" e)
    (finish-output)
    (sb-ext:exit :code 1)))
