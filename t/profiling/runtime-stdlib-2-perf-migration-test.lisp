(in-package :cl-cc/runtime/profiling/test)

(it-sequential "runtime-perf-counters-condition-path"
  :timeout
  5
  (expect (integerp (cl-cc/runtime/profiling/infra:rdtsc)) :to-be-truthy)
  (multiple-value-bind (tsc aux) (cl-cc/runtime/profiling/infra:rdtscp)
    (expect (integerp tsc) :to-be-truthy)
    (expect (= 0 aux) :to-be-truthy))
  (let ((%%signaled1 nil))
    (handler-case
        (progn
          (cl-cc/runtime/profiling/infra:rt-with-perf-counters (:cycles)
            :unreachable))
      (cl-cc/runtime/profiling/infra:perf-counters-unsupported ()
        (setf %%signaled1 t)))
    (expect %%signaled1 :to-be-truthy)))
