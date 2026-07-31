(in-package :cl-cc-runtime/test)

;;;; Tests for src/perf.lisp — FR-793 hardware performance counters.
;;;;
;;;; No real perf_event/kpc counters are available in this sandbox (macOS %perf-open
;;;; always returns fd -1), so these test the portable structure and control
;;;; logic: counter registration/lookup, the "unsupported" fallbacks, and the
;;;; timestamp helpers — not real hardware measurements. Counter struct accessors
;;;; and rt-perf-disable-counter are unexported (cl-cc/runtime:: below).
;;; ── Event catalogue + init ────────────────────────────────────────
(it-sequential
  "The supported event catalogue lists the documented counter kinds."
  (let ((names cl-cc/runtime::*perf-event-names*))
    (expect (member :cycles names) :to-be-truthy)
    (expect (member :instructions names) :to-be-truthy)
    (expect (member :cache-misses names) :to-be-truthy)))

(it-sequential
  "rt-perf-init resets the counter table and reports success."
  (expect (rt-perf-init) :to-be-truthy)
  (expect (hash-table-count cl-cc/runtime::*rt-perf-counters*) :to-equal 0))

;;; ── Enable / read / disable (unsupported hardware path) ───────────
(it-sequential "Enabling a known counter registers a struct tagged with its type/name." (rt-perf-init)
  (let ((counter (rt-perf-enable-counter :cycles)))
    (expect counter :to-be-truthy)
    (expect (cl-cc/runtime::rt-perf-counter-name counter) :to-be :cycles)
    ;; :cycles is index 0 in the event catalogue
    (expect (cl-cc/runtime::rt-perf-counter-type counter) :to-equal 0)
    ;; no hardware here, so the counter is registered but not enabled
    (expect (cl-cc/runtime::rt-perf-counter-enabled counter) :to-be-falsy)
    (expect (gethash :cycles cl-cc/runtime::*rt-perf-counters*) :to-be counter)))

(it-sequential
  "Enabling an event not in the catalogue returns NIL."
  (rt-perf-init)
  (expect (rt-perf-enable-counter :not-a-real-event) :to-be-null))

(it-sequential
  "Reading a counter that is not enabled returns NIL."
  (rt-perf-init)
  (rt-perf-enable-counter :instructions)
  (expect (rt-perf-read-counter :instructions) :to-be-null))

(it-sequential
  "Reading a counter that was never enabled returns NIL."
  (rt-perf-init)
  (expect (rt-perf-read-counter :cycles) :to-be-null))

(it-sequential
  "Disabling a counter drops it from the registry."
  (rt-perf-init)
  (rt-perf-enable-counter :cache-misses)
  (cl-cc/runtime::rt-perf-disable-counter :cache-misses)
  (expect (gethash :cache-misses cl-cc/runtime::*rt-perf-counters*) :to-be-null))

;;; ── with-perf-counters on unsupported platform ────────────────────
;;; PERF-COUNTERS-UNSUPPORTED derives from RT-RUNTIME-CONDITION, not CL:ERROR
;;; (see conditions.md), so cl-weave's SIGNALS/:TO-THROW -- which only catches
;;; ERROR subtypes -- cannot see it; a HANDLER-CASE naming the exact condition
;;; type is the only correct way to check for it.
(it-sequential
  "On a platform without HW counters, rt-with-perf-counters raises the
documented unsupported condition rather than running the body."
  (rt-perf-init)
  (expect
    (handler-case
        (progn
          (rt-with-perf-counters
            (:cycles)
            (error "body must not run when counters are unsupported"))
          nil)
      (cl-cc/runtime::perf-counters-unsupported ()
        t))
    :to-be-truthy))

;;; ── Timestamp helpers ─────────────────────────────────────────────
(it-sequential
  "rdtsc yields a non-negative integer timestamp."
  (let ((ts (rdtsc)))
    (expect (integerp ts) :to-be-truthy)
    (expect (>= ts 0) :to-be-truthy)))

(it-sequential
  "Two successive rdtsc reads are non-decreasing."
  (let ((a (rdtsc)))
    (expect (>= (rdtsc) a) :to-be-truthy)))

(it-sequential
  "rdtscp returns a timestamp and an auxiliary processor id."
  (multiple-value-bind (ts aux) (rdtscp)
    (expect (integerp ts) :to-be-truthy)
    (expect aux :to-equal 0)))
