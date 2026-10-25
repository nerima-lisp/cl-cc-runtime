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

(in-package :cl-cc/runtime/conditions/test)



;;; -----------------------------------------------------------------
;;; Wave 0: Load-Graph Verification
;;; -----------------------------------------------------------------

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

;;; -----------------------------------------------------------------
;;; Wave 3: Runtime internals
;;; -----------------------------------------------------------------

;;; -----------------------------------------------------------------
;;; Wave 1: VM ANSI Runtime Features
;;; -----------------------------------------------------------------

(it-sequential "runtime-subsystem-conditions-loaded"
  (expect (fboundp 'rt-signal) :to-be-truthy)
  (expect (fboundp 'rt-dispatch-signal) :to-be-truthy)
  (expect (fboundp 'rt-restart-case) :to-be-truthy))

;;; -----------------------------------------------------------------
;;; Wave 2-5: Integration Tests
;;; -----------------------------------------------------------------

;;; -----------------------------------------------------------------
;;; FR semantic evidence tests
;;; -----------------------------------------------------------------

;;; -----------------------------------------------------------------
;;; FR Coverage Verification
;;; -----------------------------------------------------------------

