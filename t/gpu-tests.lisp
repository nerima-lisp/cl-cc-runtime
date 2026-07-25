(in-package :cl-cc-runtime/test)
(in-suite cl-cc-unit-suite)

;;;; Tests for src/gpu.lisp — FR-400 portable GPU compute runtime.
;;;;
;;;; No real device is available in this sandbox, so these test the portable CPU
;;;; fallback: buffer bookkeeping, byte copies, dispatch-count arithmetic, the
;;;; per-work-item callback, and input validation. Buffer/kernel struct
;;;; accessors are unexported, hence cl-cc/runtime:: qualifiers.

;;; ── Buffer allocation ─────────────────────────────────────────────

(deftest gpu-alloc-sets-size-device-and-zeroed-data
  "Allocating a buffer records size/device and a zeroed byte vector."
  (let ((b (rt-gpu-buffer-alloc 16 :device :metal)))
    (assert-= 16 (cl-cc/runtime::rt-gpu-buffer-size b))
    (assert-eq :metal (cl-cc/runtime::rt-gpu-buffer-device b))
    (assert-= 16 (length (cl-cc/runtime::rt-gpu-buffer-data b)))
    (assert-true (every #'zerop (cl-cc/runtime::rt-gpu-buffer-data b)))))

(deftest gpu-alloc-defaults-to-cpu-device
  "Device defaults to :cpu."
  (assert-eq :cpu (cl-cc/runtime::rt-gpu-buffer-device (rt-gpu-buffer-alloc 4))))

(deftest gpu-alloc-rejects-negative-size
  "A negative size is rejected."
  (assert-signals error (rt-gpu-buffer-alloc -1)))

(deftest gpu-alloc-rejects-unknown-device
  "An unsupported device keyword is rejected."
  (assert-signals error (rt-gpu-buffer-alloc 4 :device :cuda)))

;;; ── Buffer copy ───────────────────────────────────────────────────

(deftest gpu-copy-transfers-bytes
  "Copy moves bytes from src into dst and returns dst."
  (let ((src (rt-gpu-buffer-alloc 4))
        (dst (rt-gpu-buffer-alloc 4)))
    (replace (cl-cc/runtime::rt-gpu-buffer-data src) #(1 2 3 4))
    (let ((result (rt-gpu-buffer-copy src dst)))
      (assert-eq dst result)
      (assert-equalp #(1 2 3 4) (cl-cc/runtime::rt-gpu-buffer-data dst)))))

(deftest gpu-copy-honors-offsets-and-size
  "Copy respects src/dst offsets and an explicit byte count."
  (let ((src (rt-gpu-buffer-alloc 4))
        (dst (rt-gpu-buffer-alloc 4)))
    (replace (cl-cc/runtime::rt-gpu-buffer-data src) #(9 8 7 6))
    (rt-gpu-buffer-copy src dst :src-offset 1 :dst-offset 2 :size 2)
    ;; dst[2],dst[3] <- src[1],src[2] = 8,7
    (assert-equalp #(0 0 8 7) (cl-cc/runtime::rt-gpu-buffer-data dst))))

(deftest gpu-copy-out-of-bounds-signals
  "A copy larger than the available bytes is rejected."
  (let ((src (rt-gpu-buffer-alloc 4))
        (dst (rt-gpu-buffer-alloc 4)))
    (assert-signals error (rt-gpu-buffer-copy src dst :size 8))))

(deftest gpu-copy-rejects-non-buffer
  "Copy validates that both arguments are buffers."
  (assert-signals error (rt-gpu-buffer-copy :not-a-buffer (rt-gpu-buffer-alloc 4))))

;;; ── Buffer free ───────────────────────────────────────────────────

(deftest gpu-free-empties-buffer
  "Freeing zeroes size, drops data, and resets device to :cpu."
  (let ((b (rt-gpu-buffer-alloc 8 :device :vulkan)))
    (assert-true (rt-gpu-buffer-free b))
    (assert-= 0 (cl-cc/runtime::rt-gpu-buffer-size b))
    (assert-= 0 (length (cl-cc/runtime::rt-gpu-buffer-data b)))
    (assert-eq :cpu (cl-cc/runtime::rt-gpu-buffer-device b))))

;;; ── Kernel compilation ────────────────────────────────────────────

(deftest gpu-kernel-compile-returns-source-for-valid-backend
  "The stub compiler validates the backend and echoes the source."
  (assert-equal "kernel main() {}"
                (rt-gpu-kernel-compile "kernel main() {}" :backend :vulkan)))

(deftest gpu-kernel-compile-rejects-bad-backend
  "An unsupported backend keyword is rejected."
  (assert-signals error (rt-gpu-kernel-compile "src" :backend :opencl)))

;;; ── Kernel launch (CPU dispatch) ──────────────────────────────────

(deftest gpu-launch-default-dims-dispatch-count-is-one
  "With default 1x1x1 grid/block the simulated dispatch count is 1."
  (let ((k (cl-cc/runtime::make-rt-gpu-kernel :name nil)))
    (assert-= 1 (rt-gpu-launch-kernel k))))

(deftest gpu-launch-dispatch-count-is-product-of-dims
  "Dispatch count equals product of all grid and block dimensions."
  (let ((k (cl-cc/runtime::make-rt-gpu-kernel
            :name nil :grid-dims '(2 3 1) :block-dims '(2 1 1))))
    ;; 2*3*1 grid * 2*1*1 block = 12 work items.
    (assert-= 12 (rt-gpu-launch-kernel k))))

(deftest gpu-launch-invokes-callback-per-work-item
  "A function-designator kernel name is called once per simulated work item."
  (let* ((hits 0)
         (k (cl-cc/runtime::make-rt-gpu-kernel
             :name (lambda (&rest args) (declare (ignore args)) (incf hits))
             :grid-dims '(3 1 1) :block-dims '(1 1 1))))
    (assert-= 3 (rt-gpu-launch-kernel k))
    (assert-= 3 hits)))

(deftest gpu-launch-rejects-non-kernel
  "Launching a non-kernel object is rejected."
  (assert-signals error (rt-gpu-launch-kernel :nope)))

(deftest gpu-launch-rejects-bad-dims
  "Dimensions must be three positive integers."
  (let ((k (cl-cc/runtime::make-rt-gpu-kernel :name nil :grid-dims '(0 1 1))))
    (assert-signals error (rt-gpu-launch-kernel k))))

;;; ── Async launch ──────────────────────────────────────────────────

(deftest gpu-launch-async-resolves-future-to-dispatch-count
  "Async launch resolves its future to the same dispatch count once run."
  (rt-scheduler-init)
  (let* ((k (cl-cc/runtime::make-rt-gpu-kernel
             :name nil :grid-dims '(2 1 1) :block-dims '(1 1 1)))
         (future (rt-gpu-launch-async k)))
    (rt-scheduler-run)
    (assert-true (cl-cc/runtime::rt-future-resolved-p future))
    (assert-= 2 (cl-cc/runtime::rt-future-value future))))
