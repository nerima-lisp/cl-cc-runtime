(in-package :cl-cc-runtime/test)

;;;; Tests for src/gpu.lisp — FR-400 portable GPU compute runtime.
;;;;
;;;; No real device is available in this sandbox, so these test the portable CPU
;;;; fallback: buffer bookkeeping, byte copies, dispatch-count arithmetic, the
;;;; per-work-item callback, and input validation. Buffer/kernel struct
;;;; accessors are unexported, hence cl-cc/runtime:: qualifiers.
;;; ── Buffer allocation ─────────────────────────────────────────────
(it-sequential
  "Allocating a buffer records size/device and a zeroed byte vector."
  (let ((b (rt-gpu-buffer-alloc 16 :device :metal)))
    (expect (cl-cc/runtime::rt-gpu-buffer-size b) :to-equal 16)
    (expect (cl-cc/runtime::rt-gpu-buffer-device b) :to-be :metal)
    (expect (length (cl-cc/runtime::rt-gpu-buffer-data b)) :to-equal 16)
    (expect (every #'zerop (cl-cc/runtime::rt-gpu-buffer-data b)) :to-be-truthy)))

(it-sequential
  "Device defaults to :cpu."
  (expect
    (cl-cc/runtime::rt-gpu-buffer-device (rt-gpu-buffer-alloc 4))
    :to-be
    :cpu))

(it-sequential
  "A negative size is rejected."
  (signals error (rt-gpu-buffer-alloc -1)))

(it-sequential
  "An unsupported device keyword is rejected."
  (signals error (rt-gpu-buffer-alloc 4 :device :cuda)))

;;; ── Buffer copy ───────────────────────────────────────────────────
(it-sequential
  "Copy moves bytes from src into dst and returns dst."
  (let ((src (rt-gpu-buffer-alloc 4))
        (dst (rt-gpu-buffer-alloc 4)))
    (replace (cl-cc/runtime::rt-gpu-buffer-data src) #(1 2 3 4))
    (let ((result (rt-gpu-buffer-copy src dst)))
      (expect result :to-be dst)
      (expect (cl-cc/runtime::rt-gpu-buffer-data dst) :to-equalp #(1 2 3 4)))))

(it-sequential "Copy respects src/dst offsets and an explicit byte count." (let ((src (rt-gpu-buffer-alloc 4))
        (dst (rt-gpu-buffer-alloc 4)))
    (replace (cl-cc/runtime::rt-gpu-buffer-data src) #(9 8 7 6))
    (rt-gpu-buffer-copy src dst :src-offset 1 :dst-offset 2 :size 2)
    ;; dst[2],dst[3] <- src[1],src[2] = 8,7
    (expect (cl-cc/runtime::rt-gpu-buffer-data dst) :to-equalp #(0 0 8 7))))

(it-sequential
  "A copy larger than the available bytes is rejected."
  (let ((src (rt-gpu-buffer-alloc 4))
        (dst (rt-gpu-buffer-alloc 4)))
    (signals error (rt-gpu-buffer-copy src dst :size 8))))

(it-sequential
  "Copy validates that both arguments are buffers."
  (signals error (rt-gpu-buffer-copy :not-a-buffer (rt-gpu-buffer-alloc 4))))

;;; ── Buffer free ───────────────────────────────────────────────────
(it-sequential
  "Freeing zeroes size, drops data, and resets device to :cpu."
  (let ((b (rt-gpu-buffer-alloc 8 :device :vulkan)))
    (expect (rt-gpu-buffer-free b) :to-be-truthy)
    (expect (cl-cc/runtime::rt-gpu-buffer-size b) :to-equal 0)
    (expect (length (cl-cc/runtime::rt-gpu-buffer-data b)) :to-equal 0)
    (expect (cl-cc/runtime::rt-gpu-buffer-device b) :to-be :cpu)))

;;; ── Kernel compilation ────────────────────────────────────────────
(it-sequential
  "The stub compiler validates the backend and echoes the source."
  (expect
    (rt-gpu-kernel-compile "kernel main() {}" :backend :vulkan)
    :to-equal
    "kernel main() {}"))

(it-sequential
  "An unsupported backend keyword is rejected."
  (signals error (rt-gpu-kernel-compile "src" :backend :opencl)))

;;; ── Kernel launch (CPU dispatch) ──────────────────────────────────
(it-sequential
  "With default 1x1x1 grid/block the simulated dispatch count is 1."
  (let ((k (cl-cc/runtime::make-rt-gpu-kernel :name nil)))
    (expect (rt-gpu-launch-kernel k) :to-equal 1)))

(it-sequential "Dispatch count equals product of all grid and block dimensions." (let ((k (cl-cc/runtime::make-rt-gpu-kernel
            :name nil :grid-dims '(2 3 1) :block-dims '(2 1 1))))
    ;; 2*3*1 grid * 2*1*1 block = 12 work items.
    (expect (rt-gpu-launch-kernel k) :to-equal 12)))

(it-sequential
  "A function-designator kernel name is called once per simulated work item."
  (let* ((hits 0)
         (k
        (cl-cc/runtime::make-rt-gpu-kernel
          :name
          (lambda (&rest args)
            (declare (ignore args))
            (incf hits))
          :grid-dims
          '(3 1 1)
          :block-dims
          '(1 1 1))))
    (expect (rt-gpu-launch-kernel k) :to-equal 3)
    (expect hits :to-equal 3)))

(it-sequential
  "Launching a non-kernel object is rejected."
  (signals error (rt-gpu-launch-kernel :nope)))

(it-sequential
  "Dimensions must be three positive integers."
  (let ((k (cl-cc/runtime::make-rt-gpu-kernel :name nil :grid-dims '(0 1 1))))
    (signals error (rt-gpu-launch-kernel k))))

;;; ── Async launch ──────────────────────────────────────────────────
(it-sequential
  "Async launch resolves its future to the same dispatch count once run."
  (rt-scheduler-init)
  (let* ((k
        (cl-cc/runtime::make-rt-gpu-kernel
          :name
          nil
          :grid-dims
          '(2 1 1)
          :block-dims
          '(1 1 1)))
         (future (rt-gpu-launch-async k)))
    (rt-scheduler-run)
    (expect (cl-cc/runtime::rt-future-resolved-p future) :to-be-truthy)
    (expect (cl-cc/runtime::rt-future-value future) :to-equal 2)))
