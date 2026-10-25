;;;; tests/runtime-subsystem-fr-tests.lisp - Runtime Subsystem FR Evidence Tests
;;;;
;;;; Evidence tests for feature requirements documented in
;;;; docs/runtime-subsystem.md.  These tests verify that every FR has
;;;; implementation evidence: symbols exist, files load, and basic
;;;; functionality works.
;;;;
;;;; FR Coverage:
;;;;   Wave 0: Load-graph verification (all source files loadable)
;;;;   Wave 1: ANSI runtime — Unicode, pprint, time, env, conditions, chars, arrays, I/O
;;;;   Wave 2: Atomics, sync, lock-free, EBR, hazard, RCU, QSBR, MVCC
;;;;   Wave 3: Safepoints, stack maps, tail calls, stack/OOM safety
;;;;   Wave 4: Concurrency — scheduler, tasks, futures, channels, actors, STM, fibers
;;;;   Wave 5: OS, async I/O, network, image, signals, mmap

(in-package :cl-cc/runtime/os/test)



;;; -----------------------------------------------------------------
;;; Wave 0: Load-Graph Verification
;;; -----------------------------------------------------------------

(it-sequential "runtime-subsystem-c-embedding-api-loaded"
  (expect (probe-file (asdf:system-relative-pathname :cl-cc-runtime "include/cl-cc.h")) :to-be-truthy)
  (expect (fboundp 'cl-cc-init) :to-be-truthy)
  (expect (fboundp 'cl-cc-eval) :to-be-truthy)
  (expect (fboundp 'cl-cc-call) :to-be-truthy)
  (expect (fboundp 'cl-cc-cleanup) :to-be-truthy)
  (expect (fboundp 'cl-cc-last-error) :to-be-truthy)
  (expect (fboundp 'cl-cc-register-callback) :to-be-truthy))

(it-sequential "runtime-subsystem-c-embedding-api-eval-call-cleanup"
  (let ((state (cl-cc-init)))
    (unwind-protect
         (progn
           (let ((value (cl-cc-eval state "(+ 20 22)")))
             (expect (cl-cc-value-kind value) :to-be :integer)
             (expect (= 42 (cl-cc-value-payload value)) :to-be-truthy))
           (cl-cc-eval state "(defun embedded-add (a b) (+ a b))")
           (let ((value (cl-cc-call state "embedded-add" 7 8)))
             (expect (cl-cc-value-kind value) :to-be :integer)
             (expect (= 15 (cl-cc-value-payload value)) :to-be-truthy))
           #+(and sbcl sb-alien-callback)
           (let ((callback (cl-cc-register-callback
                            state "identity" #'identity :arg-types '(:pointer) :return-type :pointer)))
             (expect callback :to-be-truthy)
             (expect (cl-cc-callback state "identity") :to-be callback))
           #-(and sbcl sb-alien-callback)
           (signals error (cl-cc-register-callback
              state "identity" #'identity :arg-types '(:pointer) :return-type :pointer))
           (let ((value (cl-cc-eval state "(/ 1 0)")))
             (expect (cl-cc-value-kind value) :to-be :error)
             (expect (= 1 (cl-cc-error-code (cl-cc-last-error state))) :to-be-truthy)))
      (cl-cc-cleanup state))
    (expect (cl-cc-state-closed-p state) :to-be-truthy)))

;;; -----------------------------------------------------------------
;;; Existence macros — data/logic separation
;;;
;;; define-fr-loaded-test: Prolog-style clause that checks every listed
;;; symbol is fboundp. Data = the symbol list; logic = the macro.
;;;
;;; define-fr-existence-test: more general form supporting
;;; (:f sym) fboundp / (:b sym) boundp / (:s pkg name) find-symbol.
;;; -----------------------------------------------------------------

;;; -----------------------------------------------------------------
;;; Wave 2: Sync + concurrency subsystem
;;; -----------------------------------------------------------------

;;; -----------------------------------------------------------------
;;; Wave 5: OS + I/O subsystem
;;; -----------------------------------------------------------------

(it-sequential "runtime-subsystem-os-loaded"
  (expect (fboundp 'rt-open) :to-be-truthy)
  (expect (fboundp 'rt-close) :to-be-truthy)
  (expect (fboundp 'rt-getenv) :to-be-truthy)
  (expect (fboundp 'rt-argv) :to-be-truthy)
  (expect (fboundp 'rt-exit) :to-be-truthy))

(it-sequential "runtime-subsystem-net-loaded"
  (expect (fboundp 'rt-socket) :to-be-truthy)
  (expect (fboundp 'rt-bind) :to-be-truthy)
  (expect (fboundp 'rt-listen) :to-be-truthy)
  (expect (fboundp 'rt-connect) :to-be-truthy))

;;; -----------------------------------------------------------------
;;; Wave 3: Runtime internals
;;; -----------------------------------------------------------------

;;; -----------------------------------------------------------------
;;; Wave 1: VM ANSI Runtime Features
;;; -----------------------------------------------------------------

(it-sequential "runtime-subsystem-pathname-loaded"
  (expect (fboundp 'rt-make-pathname) :to-be-truthy)
  (expect (fboundp 'rt-pathname-name) :to-be-truthy))

(it-sequential "runtime-subsystem-stream-loaded"
  (expect (fboundp 'rt-make-string-output-stream) :to-be-truthy))

(it-sequential "runtime-subsystem-time-loaded"
  (expect (fboundp 'rt-get-universal-time) :to-be-truthy)
  (expect (fboundp 'rt-get-internal-real-time) :to-be-truthy))

(it-sequential "runtime-subsystem-environment-loaded"
  (expect (fboundp 'rt-getenv) :to-be-truthy)
  (expect (fboundp 'rt-setenv) :to-be-truthy)
  (expect (fboundp 'rt-unsetenv) :to-be-truthy)
  (expect (fboundp 'rt-platform) :to-be-truthy))

;;; -----------------------------------------------------------------
;;; Wave 2-5: Integration Tests
;;; -----------------------------------------------------------------

;;; -----------------------------------------------------------------
;;; FR semantic evidence tests
;;; -----------------------------------------------------------------

;;; -----------------------------------------------------------------
;;; FR Coverage Verification
;;; -----------------------------------------------------------------

