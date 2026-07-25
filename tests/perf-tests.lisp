(in-package :cl-cc-runtime/test)
(in-suite cl-cc-unit-suite)

;;;; Tests for src/perf.lisp — FR-793 hardware performance counters.
;;;;
;;;; No real perf_event/kpc counters are available in this sandbox (macOS %perf-open
;;;; always returns fd -1), so these test the portable structure and control
;;;; logic: counter registration/lookup, the "unsupported" fallbacks, and the
;;;; timestamp helpers — not real hardware measurements. Counter struct accessors
;;;; and rt-perf-disable-counter are unexported (cl-cc/runtime:: below).

;;; ── Event catalogue + init ────────────────────────────────────────

(deftest perf-event-names-catalogue
  "The supported event catalogue lists the documented counter kinds."
  (let ((names cl-cc/runtime::*perf-event-names*))
    (assert-true (member :cycles names))
    (assert-true (member :instructions names))
    (assert-true (member :cache-misses names))))

(deftest perf-init-clears-counters
  "rt-perf-init resets the counter table and reports success."
  (assert-true (rt-perf-init))
  (assert-= 0 (hash-table-count cl-cc/runtime::*rt-perf-counters*)))

;;; ── Enable / read / disable (unsupported hardware path) ───────────

(deftest perf-enable-known-counter-registers-struct
  "Enabling a known counter registers a struct tagged with its type/name."
  (rt-perf-init)
  (let ((counter (rt-perf-enable-counter :cycles)))
    (assert-true counter)
    (assert-eq :cycles (cl-cc/runtime::rt-perf-counter-name counter))
    ;; :cycles is index 0 in the event catalogue
    (assert-= 0 (cl-cc/runtime::rt-perf-counter-type counter))
    ;; no hardware here, so the counter is registered but not enabled
    (assert-false (cl-cc/runtime::rt-perf-counter-enabled counter))
    (assert-eq counter (gethash :cycles cl-cc/runtime::*rt-perf-counters*))))

(deftest perf-enable-unknown-counter-returns-nil
  "Enabling an event not in the catalogue returns NIL."
  (rt-perf-init)
  (assert-null (rt-perf-enable-counter :not-a-real-event)))

(deftest perf-read-disabled-counter-returns-nil
  "Reading a counter that is not enabled returns NIL."
  (rt-perf-init)
  (rt-perf-enable-counter :instructions)
  (assert-null (rt-perf-read-counter :instructions)))

(deftest perf-read-unregistered-counter-returns-nil
  "Reading a counter that was never enabled returns NIL."
  (rt-perf-init)
  (assert-null (rt-perf-read-counter :cycles)))

(deftest perf-disable-counter-removes-registration
  "Disabling a counter drops it from the registry."
  (rt-perf-init)
  (rt-perf-enable-counter :cache-misses)
  (cl-cc/runtime::rt-perf-disable-counter :cache-misses)
  (assert-null (gethash :cache-misses cl-cc/runtime::*rt-perf-counters*)))

;;; ── with-perf-counters on unsupported platform ────────────────────

(deftest perf-with-counters-signals-unsupported
  "On a platform without HW counters, rt-with-perf-counters raises the
documented unsupported condition rather than running the body."
  (rt-perf-init)
  (assert-signals cl-cc/runtime::perf-counters-unsupported
    (rt-with-perf-counters (:cycles)
      (error "body must not run when counters are unsupported"))))

;;; ── Timestamp helpers ─────────────────────────────────────────────

(deftest perf-rdtsc-returns-nonnegative-integer
  "rdtsc yields a non-negative integer timestamp."
  (let ((ts (rdtsc)))
    (assert-true (integerp ts))
    (assert-true (>= ts 0))))

(deftest perf-rdtsc-is-monotonic-nondecreasing
  "Two successive rdtsc reads are non-decreasing."
  (let ((a (rdtsc)))
    (assert-true (>= (rdtsc) a))))

(deftest perf-rdtscp-returns-timestamp-and-aux
  "rdtscp returns a timestamp and an auxiliary processor id."
  (multiple-value-bind (ts aux) (rdtscp)
    (assert-true (integerp ts))
    (assert-= 0 aux)))
