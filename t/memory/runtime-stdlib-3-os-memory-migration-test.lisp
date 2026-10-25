;;;; t/memory/runtime-stdlib-3-os-memory-migration-test.lisp
(in-package :cl-cc/runtime/memory/test)

(it-sequential "rt-stackmap-compression-roundtrip"
               (let* ((slots '((8 . :object) (24 . :fixnum) (32 . :object)))
                      (compressed
                       (cl-cc/runtime/memory:rt-compress-stackmap-slots slots)))
                 (expect
                  (cl-cc/runtime/memory:rt-decompress-stackmap-slots compressed)
                  :to-equal
                  slots)
                 (expect
                  (search ".gc_map"
                          (cl-cc/runtime/memory:rt-gc-map-section-documentation))
                  :to-be-truthy)
                 (cl-cc/runtime/memory:rt-emit-gc-safepoint :kind
                                                            :test
                                                            :frame-id
                                                            :rt-test-frame
                                                            :live-slots
                                                            slots)
                 (expect
                  (let ((stackmap
                         (cl-cc/runtime/memory:rt-gc-register-stackmap
                          :rt-test-frame slots :source :test)))
                    (and (typep stackmap 'cl-cc/runtime/memory:rt-stackmap)
                         (equal slots
                                (cl-cc/runtime/memory:rt-stackmap-slots stackmap))))
                  :to-be-truthy)))
