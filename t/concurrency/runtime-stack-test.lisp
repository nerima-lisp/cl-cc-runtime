(in-package :cl-cc/runtime/concurrency/test)

(describe "segmented native stack"
  (it "maps a page-aligned segment and grows only when the downward stack pointer crosses its limit"
    (let ((*stack-segment-pool* nil))
      (let ((root (stack-segment-note-frame nil 8192)))
        ;; The mmap region is rounded up to the host's native page size, which
        ;; is 4KB on the x86_64-linux CI runner but 16KB on aarch64-darwin, so
        ;; the expectation is derived rather than a magic number.
        (expect (stack-segment-size root)
                :to-be (cl-cc/runtime/memory:rt-page-align 8192))
        (expect (> (stack-segment-base root) 0) :to-be-truthy)
        ;; One byte past ROOT's remaining capacity, so this frame overflows
        ;; it and grows a new linked segment regardless of the host's native
        ;; page size.
        (let* ((overflow (1+ (- (stack-segment-size root)
                                 (stack-segment-used root))))
               (next (stack-segment-note-frame root overflow)))
          (expect (stack-segment-prev next) :to-be root)
          (expect (stack-segment-release-frame next overflow) :to-be root)
          (expect (stack-segment-used next) :to-be 0)
          (expect (stack-segment-next next) :to-be-null)))))
  (it "maps an oversize frame safely and resets pooled linkage"
    (let ((*stack-segment-pool* nil))
      (let* ((root (stack-segment-note-frame nil 64)))
        ;; A request that FITS increments ROOT's own USED (ROOT is returned
        ;; unchanged); only a request that OVERFLOWS grows a new segment.
        ;; ROOT's USED never decreases once set, so filling it down to
        ;; exactly 63 bytes free makes every 64-byte request below overflow
        ;; it, regardless of the host's native page size.
        (stack-segment-note-frame
         root (- (stack-segment-size root)
                 (stack-segment-used root) 63))
        (let ((large (stack-segment-note-frame root 64)))
          (expect (stack-segment-prev large) :to-be root)
          (expect (>= (stack-segment-size large) 64) :to-be-truthy)
          (stack-segment-release-frame large 64)
          ;; ROOT still has only 63 bytes free, so this request overflows it
          ;; again and reclaims LARGE from the pool instead of growing a
          ;; fresh segment.
          (let ((reused (stack-segment-note-frame root 64)))
            (expect reused :to-be large)
            (expect (stack-segment-prev reused) :to-be root)
            (expect (stack-segment-next reused) :to-be-null)
            (expect (stack-segment-used reused) :to-be 64))))))
  (it "snapshots metadata and restores independently owned chains"
    (let ((*stack-segment-pool* nil))
      (expect (stack-segment-snapshot nil) :to-equal nil)
      (expect (stack-segment-restore nil) :to-be-null)
      (let* ((root (stack-segment-note-frame nil 128))
             ;; One byte past ROOT's actual mapped capacity, so CURRENT is
             ;; forced onto a second, distinct segment regardless of the
             ;; host's native page size.
             (oversize (1+ (stack-segment-size root)))
             (current (stack-segment-note-frame root oversize))
             (snapshot (stack-segment-snapshot current))
             (first (stack-segment-restore snapshot))
             (second (stack-segment-restore snapshot)))
        (expect (stack-segment-snapshot first) :to-equal snapshot)
        (expect (stack-segment-snapshot second) :to-equal snapshot)
        (expect first :not :to-be second)
        (expect (stack-segment-prev first)
                :not :to-be
                (stack-segment-prev second))
        (setf (stack-segment-used first) 1)
        (expect (stack-segment-snapshot second) :to-equal snapshot)
        (expect (release-stack-segment-chain first) :to-be-null)
        (expect (stack-segment-prev first) :to-be-null)
        (expect (stack-segment-used first) :to-be 0)
        (release-stack-segment-chain second)
        (release-stack-segment-chain current))))
  (it "cleans a partially restored chain when snapshot validation fails"
    (let ((*stack-segment-pool* nil))
      (signals error (stack-segment-restore '((8192 32) (16 17))))
      (expect (length *stack-segment-pool*) :to-be 1)
      (let ((released (first *stack-segment-pool*)))
        (expect (stack-segment-prev released) :to-be-null)
        (expect (stack-segment-next released) :to-be-null)
        (expect (stack-segment-used released) :to-be 0)))))
