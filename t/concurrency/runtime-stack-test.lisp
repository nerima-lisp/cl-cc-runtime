(in-package :cl-cc/runtime/concurrency/test)

(describe "segmented native stack"
  (it "maps a page-aligned segment and grows only when the downward stack pointer crosses its limit"
    (let ((cl-cc/runtime::*stack-segment-pool* nil))
      (let ((root (cl-cc/runtime::stack-segment-note-frame nil 8192)))
        ;; The mmap region is rounded up to the host's native page size, which
        ;; is 4KB on the x86_64-linux CI runner but 16KB on aarch64-darwin, so
        ;; the expectation is derived rather than a magic number.
        (expect (cl-cc/runtime::stack-segment-size root)
                :to-be (cl-cc/runtime::rt-page-align 8192))
        (expect (> (cl-cc/runtime::stack-segment-base root) 0) :to-be-truthy)
        ;; One byte past ROOT's remaining capacity, so this frame overflows
        ;; it and grows a new linked segment regardless of the host's native
        ;; page size.
        (let* ((overflow (1+ (- (cl-cc/runtime::stack-segment-size root)
                                 (cl-cc/runtime::stack-segment-used root))))
               (next (cl-cc/runtime::stack-segment-note-frame root overflow)))
          (expect (cl-cc/runtime::stack-segment-prev next) :to-be root)
          (expect (cl-cc/runtime::stack-segment-release-frame next overflow) :to-be root)
          (expect (cl-cc/runtime::stack-segment-used next) :to-be 0)
          (expect (cl-cc/runtime::stack-segment-next next) :to-be-null)))))
  (it "maps an oversize frame safely and resets pooled linkage"
    (let ((cl-cc/runtime::*stack-segment-pool* nil))
      (let* ((root (cl-cc/runtime::stack-segment-note-frame nil 64)))
        ;; A request that FITS increments ROOT's own USED (ROOT is returned
        ;; unchanged); only a request that OVERFLOWS grows a new segment.
        ;; ROOT's USED never decreases once set, so filling it down to
        ;; exactly 63 bytes free makes every 64-byte request below overflow
        ;; it, regardless of the host's native page size.
        (cl-cc/runtime::stack-segment-note-frame
         root (- (cl-cc/runtime::stack-segment-size root)
                 (cl-cc/runtime::stack-segment-used root) 63))
        (let ((large (cl-cc/runtime::stack-segment-note-frame root 64)))
          (expect (cl-cc/runtime::stack-segment-prev large) :to-be root)
          (expect (>= (cl-cc/runtime::stack-segment-size large) 64) :to-be-truthy)
          (cl-cc/runtime::stack-segment-release-frame large 64)
          ;; ROOT still has only 63 bytes free, so this request overflows it
          ;; again and reclaims LARGE from the pool instead of growing a
          ;; fresh segment.
          (let ((reused (cl-cc/runtime::stack-segment-note-frame root 64)))
            (expect reused :to-be large)
            (expect (cl-cc/runtime::stack-segment-prev reused) :to-be root)
            (expect (cl-cc/runtime::stack-segment-next reused) :to-be-null)
            (expect (cl-cc/runtime::stack-segment-used reused) :to-be 64))))))
  (it "snapshots metadata and restores independently owned chains"
    (let ((cl-cc/runtime::*stack-segment-pool* nil))
      (expect (cl-cc/runtime::stack-segment-snapshot nil) :to-equal nil)
      (expect (cl-cc/runtime::stack-segment-restore nil) :to-be-null)
      (let* ((root (cl-cc/runtime::stack-segment-note-frame nil 128))
             ;; One byte past ROOT's actual mapped capacity, so CURRENT is
             ;; forced onto a second, distinct segment regardless of the
             ;; host's native page size.
             (oversize (1+ (cl-cc/runtime::stack-segment-size root)))
             (current (cl-cc/runtime::stack-segment-note-frame root oversize))
             (snapshot (cl-cc/runtime::stack-segment-snapshot current))
             (first (cl-cc/runtime::stack-segment-restore snapshot))
             (second (cl-cc/runtime::stack-segment-restore snapshot)))
        (expect (cl-cc/runtime::stack-segment-snapshot first) :to-equal snapshot)
        (expect (cl-cc/runtime::stack-segment-snapshot second) :to-equal snapshot)
        (expect first :not :to-be second)
        (expect (cl-cc/runtime::stack-segment-prev first)
                :not :to-be
                (cl-cc/runtime::stack-segment-prev second))
        (setf (cl-cc/runtime::stack-segment-used first) 1)
        (expect (cl-cc/runtime::stack-segment-snapshot second) :to-equal snapshot)
        (expect (cl-cc/runtime::release-stack-segment-chain first) :to-be-null)
        (expect (cl-cc/runtime::stack-segment-prev first) :to-be-null)
        (expect (cl-cc/runtime::stack-segment-used first) :to-be 0)
        (cl-cc/runtime::release-stack-segment-chain second)
        (cl-cc/runtime::release-stack-segment-chain current))))
  (it "cleans a partially restored chain when snapshot validation fails"
    (let ((cl-cc/runtime::*stack-segment-pool* nil))
      (signals error (cl-cc/runtime::stack-segment-restore '((8192 32) (16 17))))
      (expect (length cl-cc/runtime::*stack-segment-pool*) :to-be 1)
      (let ((released (first cl-cc/runtime::*stack-segment-pool*)))
        (expect (cl-cc/runtime::stack-segment-prev released) :to-be-null)
        (expect (cl-cc/runtime::stack-segment-next released) :to-be-null)
        (expect (cl-cc/runtime::stack-segment-used released) :to-be 0)))))
