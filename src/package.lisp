;;;; packages/runtime/src/package.lisp - CL-CC Runtime Library Package

(defpackage #:cl-cc/runtime
  (:use #:cl)
  (:shadowing-import-from #:cl-cc/runtime/values #:make-hash-table)
  (:import-from #:cl-cc/runtime/clos
                #:*rt-class-registry* #:*rt-generic-function-registry* #:rt-call-generic #:rt-call-next-method #:rt-class-name
                #:rt-class-of #:rt-compute-applicable-methods #:rt-defclass #:rt-find-class #:rt-make-instance
                #:rt-make-instance-0 #:rt-next-method-p #:rt-register-method #:rt-slot-boundp #:rt-slot-exists-p
                #:rt-slot-makunbound #:rt-slot-set #:rt-slot-value
                #:%rt-classify-arg #:%rt-cpl-walk #:%rt-eql-specializer-p #:%rt-extract-eql-specializer-keys
                #:*rt-method-context-stack* #:*rt-primitive-type-classifiers*
  )
  (:import-from #:cl-cc/runtime/compression
                #:adler32 #:crc32 #:gzip-compress #:gzip-decompress #:zlib-compress
                #:zlib-decompress
  )
  (:import-from #:cl-cc/runtime/concurrency
                #:*rt-dl-enabled* #:*rt-dl-thread-locks* #:*rt-dl-thread-waits* #:*rt-fork-join-pool* #:*rt-handler-stack*
                #:*rt-native-thread-registry* #:*rt-work-stealing-scheduler* #:make-rt-effect #:make-rt-handler-state #:opt-pass-stm
                #:rt-actor-receive #:rt-actor-send #:rt-all-threads #:rt-async #:rt-async-channel
                #:rt-async-cps #:rt-async-cps-transform #:rt-async-defun #:rt-async-lambda #:rt-async-recv
                #:rt-async-send #:rt-async-submit #:rt-atomically #:rt-await #:rt-await*
                #:rt-barrier-reset #:rt-barrier-wait #:rt-channel-close #:rt-channel-recv #:rt-channel-select
                #:rt-channel-send #:rt-channel-try-recv #:rt-channel-try-send #:rt-condition-notify #:rt-condition-notify-all
                #:rt-condition-wait #:rt-condition-wait-until #:rt-context-cancel #:rt-context-cancelled-p #:rt-context-get-deadline
                #:rt-context-spawn #:rt-context-value #:rt-current-handler #:rt-current-thread #:rt-current-thread-id
                #:rt-deadlock-after-lock #:rt-deadlock-after-unlock #:rt-deadlock-before-lock #:rt-deadlock-detect #:rt-deadlock-init
                #:rt-destroy-thread #:rt-ebr-collect #:rt-ebr-current-local #:rt-ebr-enter #:rt-ebr-init
                #:rt-ebr-leave #:rt-ebr-register-thread #:rt-ebr-retire #:rt-ebr-unregister-thread #:rt-effect
                #:rt-effect-error #:rt-effect-name #:rt-effect-p #:rt-effect-payload #:rt-effect-read
                #:rt-effect-state #:rt-effect-write #:rt-fiber #:rt-fiber-async #:rt-fiber-await
                #:rt-fiber-block #:rt-fiber-done-p #:rt-fiber-local #:rt-fiber-p #:rt-fiber-resume
                #:rt-fiber-schedule #:rt-fiber-spawn #:rt-fiber-status-failed-p #:rt-fiber-yield #:rt-future-await
                #:rt-future-done-p #:rt-future-resolve #:rt-future-then #:rt-green-thread #:rt-green-thread-error
                #:rt-green-thread-p #:rt-green-thread-result #:rt-green-thread-spawn #:rt-green-thread-status #:rt-handle
                #:rt-handler-state #:rt-handler-state-handlers #:rt-handler-state-p #:rt-hp-all-protected #:rt-hp-clear
                #:rt-hp-clear-all #:rt-hp-init #:rt-hp-protect #:rt-hp-reclaim #:rt-hp-register-thread
                #:rt-hp-retire #:rt-hp-retire-object #:rt-hp-scan #:rt-hp-set-threshold #:rt-hp-unregister-thread
                #:rt-interrupt-thread #:rt-lfhash-cas #:rt-lfhash-count #:rt-lfhash-get #:rt-lfhash-remove
                #:rt-lfqueue-empty-p #:rt-lfqueue-pop #:rt-lfqueue-push #:rt-lfstack-empty-p #:rt-lfstack-pop
                #:rt-lfstack-push #:rt-lock #:rt-lockfree-init #:rt-make-actor #:rt-make-barrier
                #:rt-make-channel #:rt-make-condition-variable #:rt-make-fiber #:rt-make-future #:rt-make-lfhash-map
                #:rt-make-lfqueue #:rt-make-lfstack #:rt-make-lock #:rt-make-mutex #:rt-make-once
                #:rt-make-recursive-mutex #:rt-make-rwlock #:rt-make-scheduler #:rt-make-semaphore #:rt-make-spsc-queue
                #:rt-make-thread #:rt-make-tvar #:rt-make-work-stealing-scheduler #:rt-mutex-lock #:rt-mutex-owner
                #:rt-mutex-try-lock #:rt-mutex-unlock #:rt-native-thread #:rt-native-thread-p #:rt-once-call
                #:rt-parallel-algo-init #:rt-parallel-for #:rt-parallel-map #:rt-parallel-prefix-scan #:rt-parallel-reduce
                #:rt-parallel-sort #:rt-perform #:rt-qsbr-init #:rt-qsbr-quiescent #:rt-qsbr-register-thread
                #:rt-qsbr-retire #:rt-qsbr-synchronize #:rt-qsbr-thread-count #:rt-qsbr-unregister-thread #:rt-rcu-assign-pointer
                #:rt-rcu-call #:rt-rcu-dereference #:rt-rcu-init #:rt-rcu-read-lock #:rt-rcu-synchronize
                #:rt-read-tvar #:rt-recursive-mutex-try-lock #:rt-resume #:rt-retry #:rt-run-fibers
                #:rt-run-green-threads #:rt-rwlock-try-read-lock #:rt-rwlock-try-write-lock #:rt-scheduler-init #:rt-scheduler-run
                #:rt-scheduler-steal #:rt-semaphore-signal #:rt-semaphore-try-wait #:rt-semaphore-wait #:rt-sleep-task
                #:rt-spawn #:rt-spsc-capacity #:rt-spsc-empty-p #:rt-spsc-full-p #:rt-spsc-init
                #:rt-spsc-pop #:rt-spsc-push #:rt-spsc-reset #:rt-spsc-size #:rt-spsc-try-pop
                #:rt-spsc-try-push #:rt-stm-conflict #:rt-stm-current-cache-hits #:rt-stm-current-effects #:rt-stm-retry
                #:rt-stm-transaction #:rt-sync-init #:rt-thread-alive-p #:rt-thread-join #:rt-thread-name
                #:rt-thread-yield #:rt-try-lock #:rt-tvar #:rt-tvar-p #:rt-tvar-value-unsafe
                #:rt-tvar-version-unsafe #:rt-unlock #:rt-with-context #:rt-with-context-value #:rt-with-ebr-critical
                #:rt-with-handler #:rt-with-lock #:rt-with-mutex #:rt-with-rcu-read #:rt-with-read-lock
                #:rt-with-recursive-mutex #:rt-with-remaining-timeout #:rt-with-try-mutex #:rt-with-write-lock #:rt-work-deque
                #:rt-work-deque-count #:rt-work-deque-p #:rt-work-deque-pop-front #:rt-work-deque-push-front #:rt-work-deque-steal-back
                #:rt-work-stealing-init #:rt-work-stealing-maybe-grow #:rt-work-stealing-run #:rt-work-stealing-scheduler #:rt-work-stealing-scheduler-p
                #:rt-work-stealing-submit #:rt-worker #:rt-worker-p #:rt-worker-run-once #:rt-write-tvar
                #:rt-yield
                #:%make-rt-green-thread #:%rt-scheduler-dequeue #:%rt-scheduler-enqueue
                #:%rt-scheduler-wake-sleepers #:%rt-supervisor-restart #:%rt-task-group-collect-errors
                #:%rt-worker-steal #:*ebr-mutex* #:*ebr-thread-locals* #:*rt-current-context*
                #:*rt-current-effect* #:*rt-current-fiber* #:*rt-current-green-thread* #:*rt-fiber-ready*
                #:*rt-global-scheduler* #:*rt-parallel-threshold* #:*rt-rcu-readers* #:*stack-segment-pool*
                #:make-rt-context #:make-rt-task-group #:make-rt-work-deque #:release-stack-segment-chain
                #:rt-actor-clear-registry #:rt-actor-link #:rt-actor-links #:rt-actor-m #:rt-actor-mailbox
                #:rt-actor-monitor #:rt-actor-monitors #:rt-actor-name #:rt-actor-register #:rt-actor-spawn
                #:rt-actor-status #:rt-actor-stop #:rt-actor-task #:rt-actor-unregister #:rt-actor-whereis
                #:rt-all-futures #:rt-channel-buffered-p #:rt-channel-capacity #:rt-channel-count
                #:rt-channel-open-p #:rt-context-cancelled #:rt-context-copy #:rt-context-dl
                #:rt-context-set-value #:rt-ebr-advance-epoch #:rt-ebr-can-advance-p #:rt-ebr-local-in-critical
                #:rt-ebr-local-retired-0 #:rt-ebr-local-retired-1 #:rt-ebr-reclaim #:rt-effect-condition
                #:rt-effect-condition-effect #:rt-fiber-error #:rt-fiber-id #:rt-fiber-result
                #:rt-fiber-set-continuation #:rt-fiber-status #:rt-fiber-yielded-value #:rt-fork-join
                #:rt-green-thread-cancelled-p #:rt-green-thread-priority #:rt-lfhash-put #:rt-make-supervisor
                #:rt-make-thread-pool #:rt-mutex-host-mutex #:rt-mutex-name #:rt-mutex-p
                #:rt-native-thread-error #:rt-native-thread-state #:rt-parallel-p #:rt-parallel-scan
                #:rt-rcu-read-unlock #:rt-recursive-mutex-depth #:rt-recursive-mutex-lock
                #:rt-recursive-mutex-owner #:rt-recursive-mutex-unlock #:rt-rwlock-read-lock
                #:rt-rwlock-read-unlock #:rt-rwlock-readers #:rt-rwlock-write-lock #:rt-rwlock-write-unlock
                #:rt-scheduler #:rt-scheduler-ready #:rt-scheduler-sleeping #:rt-semaphore-count #:rt-spawn-high
                #:rt-spawn-low #:rt-supervisor-children #:rt-supervisor-restarts #:rt-supervisor-strategy
                #:rt-task-cancel #:rt-task-cancelled-p #:rt-task-group #:rt-task-group-add
                #:rt-task-group-cancel #:rt-task-group-cancelled-p #:rt-task-group-errors
                #:rt-task-group-errors-list #:rt-task-group-tasks #:rt-task-group-wait #:rt-task-result
                #:rt-thread-pool-run #:rt-thread-pool-shutdown #:rt-thread-pool-start #:rt-thread-pool-submit
                #:rt-thread-pool-threads #:rt-with-task-group #:rt-work-stealing-scheduler-workers
                #:rt-worker-deque #:rt-worker-steals #:rt-worker-tasks-executed #:stack-segment-base
                #:stack-segment-next #:stack-segment-note-frame #:stack-segment-prev
                #:stack-segment-release-frame #:stack-segment-restore #:stack-segment-size
                #:stack-segment-snapshot #:stack-segment-used
  )
  (:import-from #:cl-cc/runtime/conditions
                #:*handler-stack* #:*restart-stack* #:*rt-debugger-hook* #:make-rt-handler #:make-rt-restart
                #:rt-arithmetic-error #:rt-cell-error #:rt-cerror #:rt-control-error #:rt-dispatch-restart
                #:rt-dispatch-signal #:rt-division-by-zero #:rt-establish-handler #:rt-establish-restart #:rt-file-error
                #:rt-find-handler #:rt-find-restart #:rt-floating-point-overflow #:rt-floating-point-underflow #:rt-gc-pressure-warning
                #:rt-handler #:rt-handler-condition-type #:rt-handler-handler-function #:rt-handler-p #:rt-invoke-debugger-hook
                #:rt-invoke-restart #:rt-oom-condition #:rt-pop-handler #:rt-pop-restart #:rt-program-error
                #:rt-push-handler #:rt-push-restart #:rt-restart #:rt-restart-bind #:rt-restart-case
                #:rt-restart-function #:rt-restart-name #:rt-restart-p #:rt-runtime-condition #:rt-runtime-error
                #:rt-serious-condition #:rt-signal #:rt-signal-error #:rt-simple-type-error #:rt-storage-condition
                #:rt-stream-error #:rt-type-error #:rt-unbound-variable #:rt-undefined-function #:rt-warn-fn
                #:rt-warning #:rt-with-debugger-hook
                #:rt-oom-limit-words #:rt-oom-requested-words #:rt-oom-used-words #:rt-stack-overflow
                #:rt-stack-overflow-depth #:rt-stack-overflow-limit
  )
  (:import-from #:cl-cc/runtime/cryptography
                #:rt-base64-decode #:rt-base64-encode #:rt-hmac-sha256 #:rt-sha256 #:rt-sha256-string
                #:rt-sha512
  )
  (:import-from #:cl-cc/runtime/dynamic-binding
                #:rt-boundp #:rt-make-symbol #:rt-makunbound #:rt-set-symbol-value #:rt-symbol-value
                #:rt-with-dynamic-binding
                #:*rt-dynamic-binding-stacks* #:*rt-global-var-registry* #:*rt-special-variable-metadata*
                #:rt-dynamic-bind #:rt-dynamic-unbind #:rt-register-special-variable
                #:rt-special-variable-global-only-p
  )
  (:import-from #:cl-cc/runtime/execution
                #:*rt-code-cache* #:rt-apply-fn #:rt-call-fn #:rt-check-stack-overflow #:rt-closure-ref
                #:rt-code-cache-evict #:rt-code-cache-lookup #:rt-code-cache-stats #:rt-code-cache-store #:rt-functionp
                #:rt-gc-unload-code #:rt-make-closure #:rt-poison-return-address #:rt-register-function #:rt-return-address-poisoned-p
                #:rt-unpoison-return-address #:rt-with-call-stack-guard
                #:*max-call-stack-depth* #:*rt-call-stack-depth* #:make-rt-code-cache #:rt-closure-obj-p
  )
  (:import-from #:cl-cc/runtime/images
                #:*saved-core-pathname* #:rt-capture-image-state #:rt-hot-reload #:rt-image-init #:rt-image-register-global
                #:rt-image-register-restore-hook #:rt-load-core #:rt-load-image #:rt-restore-image-state #:rt-save-core
                #:rt-save-image
                #:*rt-code-version* #:*rt-image-globals* #:*rt-image-restore-hooks* #:make-rt-image
                #:make-rt-image-header #:rt-image-code-version #:rt-image-globals #:rt-image-p
                #:rt-validate-image
  )
  (:import-from #:cl-cc/runtime/memory
                #:%rt-gc-work-stealing-drain #:%rt-phantom-ref-referent #:*compacting-gc-enabled* #:*concurrent-gc-enabled* #:*frame-pool*
                #:*frame-pool-top* #:*gc-allocation-rate-limit-words-per-sec* #:*gc-back-pressure-threshold* #:*gc-compact-after-major-cycles* #:*gc-epsilon-enabled*
                #:*gc-inhibit-during-signals* #:*gc-nursery-size* #:*gc-old-size-words* #:*gc-pacer-enabled* #:*gc-pause-target-ms*
                #:*gc-pending* #:*gc-probes-enabled* #:*gc-profile-enabled* #:*gc-profile-interval* #:*gc-regions*
                #:*gc-stress-mode* #:*gc-tenuring-threshold* #:*gc-threads* #:*gc-verify-after-collect* #:*gc-worker-count*
                #:*gc-young-size-words* #:*large-object-threshold* #:*pending-finalizers* #:*rt-asan-enabled* #:*rt-concurrent-gc-enabled-p*
                #:*rt-concurrent-gc-mutator-assist-p* #:*rt-concurrent-gc-stw-phases* #:*rt-concurrent-gc-write-barrier-mode* #:*rt-current-pinning-heap* #:*rt-default-reference-queue*
                #:*rt-ephemeron-registry* #:*rt-finalization-queue* #:*rt-finalizer-registry* #:*rt-gc-alloc-hooks* #:*rt-gc-death-hooks*
                #:*rt-gc-safe-region-depths* #:*rt-hwasan-enabled* #:*rt-immortal-registry* #:*rt-msan-enabled* #:*rt-numa-enabled*
                #:*rt-reference-registry* #:*rt-region-mixed-collection-enabled-p* #:*rt-tsan-enabled* #:*rt-tsan-thread-id* #:*rt-ubsan-enabled*
                #:*rt-use-barrier-batching* #:*satb-queue* #:*use-huge-pages* #:*write-barrier-opt-enabled* #:+frame-arg-end+
                #:+frame-arg-start+ #:+frame-callee-save-end+ #:+frame-callee-save-start+ #:+frame-caller-save-end+ #:+frame-caller-save-start+
                #:+frame-pool-size+ #:+frame-register-count+ #:+frame-return-reg+ #:+frame-spill-start+ #:+gc-card-size-words+
                #:+gc-region-size+ #:+rt-map-fixed+ #:+rt-prot-none+ #:arena-alloc #:arena-reset
                #:colored-pointer-p #:concurrent-mark-worker #:enable-epsilon-gc #:epsilon-gc-enabled-p #:estimate-region-garbage-ratio
                #:frame-pool-acquire #:frame-pool-release #:frame-reg-get #:frame-reg-set #:frame-reset
                #:gc-region #:header-clear-finalized #:header-clear-gray #:header-clear-mark #:header-finalized-p
                #:header-forwarding-p #:header-forwarding-ptr #:header-gray-p #:header-make-forwarding-ptr #:header-marked-p
                #:header-set-finalized #:header-set-gray #:header-set-mark #:huge-pages-enabled-p #:initialize-frame-pool
                #:make-arena #:make-gc-region #:make-object-pool #:make-rt-ephemeron #:make-rt-header
                #:make-rt-heap #:make-rt-stackmap #:make-rt-tlab #:mmap-advice #:mmap-array
                #:mmap-close #:mmap-file #:mmap-sync #:pointer-color #:pool-acquire
                #:pool-release #:register-finalizer #:rt-alloc #:rt-alloc-call-frame #:rt-allocate-anonymous-memory
                #:rt-allocate-code-memory #:rt-allocator-init #:rt-arena #:rt-arena-block #:rt-arena-block-offset
                #:rt-arena-cursor #:rt-card-clear #:rt-card-clear-all #:rt-card-dirty-p #:rt-card-index
                #:rt-card-mark-dirty #:rt-card-summary-clean-block-p #:rt-card-summary-update #:rt-close-region #:rt-compress-object-ref
                #:rt-compress-stackmap-slots #:rt-decompress-object-ref #:rt-decompress-stackmap-slots #:rt-emit-gc-safepoint #:rt-ephemeron
                #:rt-ephemeron-key #:rt-ephemeron-value #:rt-free #:rt-free-call-frame #:rt-gc-add-root
                #:rt-gc-add-root-typed #:rt-gc-alloc #:rt-gc-clear-stack-allocated-objects #:rt-gc-compact-old-space #:rt-gc-concurrent-assist
                #:rt-gc-concurrent-sweep #:rt-gc-concurrent-sweep-worker #:rt-gc-configure-concurrent-mode #:rt-gc-current-cycle #:rt-gc-detect-worker-count
                #:rt-gc-drain-satb-thread-queues #:rt-gc-dynamic-tenure #:rt-gc-enter-safe-region #:rt-gc-flush-barrier-buffer #:rt-gc-generate-stackmap-stub
                #:rt-gc-heap-census #:rt-gc-heap-dump-dot #:rt-gc-heap-snapshot #:rt-gc-inhibit-p #:rt-gc-leave-safe-region
                #:rt-gc-major-collect #:rt-gc-map-heap-objects #:rt-gc-map-section-documentation #:rt-gc-minor-collect #:rt-gc-numa-affinity
                #:rt-gc-pacer-maybe-throttle #:rt-gc-parallel-mark #:rt-gc-parallel-root-scan #:rt-gc-parallel-sweep #:rt-gc-probe-alloc
                #:rt-gc-probe-gc-end #:rt-gc-probe-gc-start #:rt-gc-process-references #:rt-gc-profile-report #:rt-gc-profile-sample
                #:rt-gc-region-handle-evacuation-failure #:rt-gc-region-mixed-collect #:rt-gc-region-select-mixed #:rt-gc-register-alloc-hook #:rt-gc-register-death-hook
                #:rt-gc-register-stack-allocated-object #:rt-gc-register-stackmap #:rt-gc-register-thread #:rt-gc-remove-root #:rt-gc-request
                #:rt-gc-safepoint-check #:rt-gc-satb-enqueue #:rt-gc-scan-stackmaps #:rt-gc-select-policy #:rt-gc-should-run-compaction-p
                #:rt-gc-simd-zero-fill #:rt-gc-stack-allocated-object-p #:rt-gc-stats #:rt-gc-tlab-alloc #:rt-gc-tlab-retire-all
                #:rt-gc-unregister-thread #:rt-gc-verify-heap #:rt-gc-verify-tri-color-invariant #:rt-gc-write-barrier #:rt-header-age
                #:rt-header-gc-bits #:rt-header-increment-age #:rt-header-shape-id #:rt-header-size #:rt-header-type-tag
                #:rt-heap #:rt-heap-addr-p #:rt-heap-age-hist #:rt-heap-barrier-buffer #:rt-heap-card-summary
                #:rt-heap-card-table #:rt-heap-compaction-trigger-fraction #:rt-heap-fragmentation-pct #:rt-heap-free-list #:rt-heap-gc-inhibit
                #:rt-heap-gc-pause-max #:rt-heap-gc-pause-total #:rt-heap-gc-pending #:rt-heap-gc-state #:rt-heap-initialize-regions
                #:rt-heap-interleave #:rt-heap-large-obj-base #:rt-heap-large-obj-free #:rt-heap-large-obj-size #:rt-heap-large-obj-threshold
                #:rt-heap-major-gc-count #:rt-heap-max-heap-words #:rt-heap-maybe-grow #:rt-heap-maybe-shrink #:rt-heap-minor-gc-count
                #:rt-heap-num-cards #:rt-heap-object-header #:rt-heap-object-size #:rt-heap-occupancy-pct #:rt-heap-old-base
                #:rt-heap-old-free #:rt-heap-old-size #:rt-heap-pressure-hooks #:rt-heap-pressure-threshold-high #:rt-heap-pressure-threshold-low
                #:rt-heap-randomize-base #:rt-heap-ref #:rt-heap-region #:rt-heap-region-for-address #:rt-heap-region-size-words
                #:rt-heap-regions #:rt-heap-register-pressure-hook #:rt-heap-roots #:rt-heap-satb-queue #:rt-heap-set
                #:rt-heap-set-header #:rt-heap-should-compact-p #:rt-heap-shrink-threshold #:rt-heap-total-alloc-words #:rt-heap-words
                #:rt-heap-words-collected #:rt-heap-words-promoted #:rt-heap-young-free #:rt-heap-young-from-base #:rt-heap-young-semi-size
                #:rt-heap-young-to-base #:rt-huge-page-mmap #:rt-immortal-objects-count #:rt-immortal-p #:rt-install-stack-guard
                #:rt-large-object-size-p #:rt-los-alloc #:rt-make-ephemeron #:rt-make-immortal #:rt-make-phantom-ref
                #:rt-make-region #:rt-make-soft-ref #:rt-make-weak-pointer #:rt-make-weak-ref #:rt-mmap-init
                #:rt-mmap-raw #:rt-mmap-ref #:rt-mmap-region #:rt-mmap-region-address #:rt-mmap-region-length
                #:rt-mmap-region-p #:rt-mmap-region-released-p #:rt-mmap-set #:rt-mprotect #:rt-munmap-raw
                #:rt-numa-local-alloc #:rt-numa-node-of-thread #:rt-object-pinned-p #:rt-object-pointer-slots #:rt-object-pool
                #:rt-old-addr-p #:rt-phantom-ref #:rt-pin-object #:rt-ref-clear-p #:rt-ref-get
                #:rt-reference-queue-process #:rt-region-active-p #:rt-region-alloc #:rt-region-capacity #:rt-region-deref
                #:rt-region-ref-valid-p #:rt-region-used #:rt-release-code-memory #:rt-resource-limit #:rt-run-pending-finalizers
                #:rt-sanitizer-poison-address #:rt-sanitizer-reset-state #:rt-sanitizer-set-address-tag #:rt-sanitizer-unpoison-address #:rt-set-resource-limit
                #:rt-size-class-for #:rt-soft-ref #:rt-soft-ref-referent #:rt-stackmap #:rt-stackmap-slots
                #:rt-tlab #:rt-tlab-base #:rt-tlab-free #:rt-tlab-limit #:rt-tlab-p
                #:rt-tlab-retired-p #:rt-tlab-thread-id #:rt-tlab-waste-bytes #:rt-unpin-object #:rt-weak-pointer-p
                #:rt-weak-pointer-value #:rt-weak-ref #:rt-weak-ref-referent #:rt-with-region #:rt-young-addr-p
                #:satb-drain-queue #:satb-write-barrier #:set-pointer-color #:strip-pointer-color #:try-enable-huge-pages
                #:vm-frame #:vm-frame-closure #:vm-frame-p #:vm-frame-pc #:vm-frame-registers
                #:vm-frame-return-frame #:vm-frame-sp #:with-arena #:with-arena-region #:with-mmap
                #:with-pinned-objects #:without-gcing
                #:%gc-cheney-scan #:%gc-coalesce-free-list #:%gc-scan-dirty-cards #:%gc-sweep-old-space
                #:%gc-update-promoted #:%make-vm-frame #:%rt-gc-note-pause #:%rt-gc-partition-list
                #:%rt-gc-process-ephemerons #:%rt-gc-process-finalizers #:%rt-gc-process-weak-hash-tables
                #:%rt-gc-process-weak-references #:%rt-gc-queue-pop #:%rt-gc-queue-push-list
                #:%rt-gc-run-worker-tasks #:%rt-gc-run-workers-with-progress #:%rt-gc-sb-thread-mutex
                #:%rt-gc-steal-one #:%rt-gc-tlab-for #:%rt-gc-tune-nursery #:%rt-resolve-sb-thread-function
                #:%rt-tsan-current-thread-id #:%rt-with-sanitizer-map-lock #:*gc-compaction-enabled*
                #:*gc-lazy-sweep-enabled* #:*gc-max-pause-ms* #:*gc-profile-bytes-since-sample*
                #:*gc-profile-current-function* #:*gc-profile-samples* #:*gc-throughput-target*
                #:*gc-tlab-retire-fill* #:*gc-tlab-size-words* #:*rt-gc-stackmap-table*
                #:*rt-gc-work-stealing-locks* #:*rt-gc-work-stealing-processor* #:*rt-gc-work-stealing-queues*
                #:*rt-gc-work-stealing-worker-index* #:*rt-low-promotion-cycles* #:*rt-minor-gc-window-start*
                #:*rt-thread-local-heaps* #:*rt-use-slab-allocator* #:*vm-call-frame-pool-limit*
                #:+alloc-large-threshold+ #:+color-finalizable+ #:+color-marked+ #:+color-remapped+
                #:+colored-pointer-tag-bits+ #:+rt-map-anonymous+ #:+rt-page-size+ #:+rt-prot-read+
                #:+rt-prot-write+ #:gc-region-garbage-ratio #:gc-region-generation #:gc-region-live-bytes
                #:rt-arena-block-size #:rt-arena-buffer #:rt-arena-p #:rt-check-heap-pressure-thresholds
                #:rt-free-list-bin-index #:rt-free-list-find #:rt-free-list-insert #:rt-gc-auto-configure-heap
                #:rt-gc-lazy-sweep-step #:rt-heap-free-bins #:rt-heap-free-list-blocks
                #:rt-heap-incremental-work-budget #:rt-heap-interleaved-regions #:rt-heap-madvise-hugepage
                #:rt-heap-madvise-sequential #:rt-heap-madvise-willneed #:rt-heap-numa-gc-schedule
                #:rt-heap-numa-node-map #:rt-heap-pause-exceeded-count #:rt-heap-region-evacuation-failed-p
                #:rt-mmap #:rt-munmap #:rt-object-pool-pool #:rt-page-align #:rt-signal-oom
                #:rt-stackmap-frame-id #:rt-stackmap-p #:rt-stackmap-source
  )
  (:import-from #:cl-cc/runtime/observability
                #:*default-logger* #:*rt-logger* #:*rt-otel-span* #:+level-debug+ #:+level-error+
                #:+level-fatal+ #:+level-info+ #:+level-warn+ #:call-with-captured-log-context #:capture-log-context
                #:derive-logger #:gc-stats #:log-condition #:log-context-snapshot-p #:log-debug
                #:log-default-debug #:log-default-error #:log-default-fatal #:log-default-info #:log-default-warn
                #:log-error #:log-fatal #:log-info #:log-record-fields #:log-warn
                #:logger-child #:logger-with #:make-function-handler #:make-json-handler #:make-logger
                #:make-rt-otel-event #:make-rt-otel-span #:make-text-handler #:prometheus-text-format #:rt-counter-increment!
                #:rt-gauge-set! #:rt-histogram-observe! #:rt-log #:rt-make-counter #:rt-make-gauge
                #:rt-make-histogram #:rt-metrics-format-prometheus #:rt-otel-add-event #:rt-otel-end-span #:rt-otel-event
                #:rt-otel-event-attributes #:rt-otel-event-name #:rt-otel-event-time #:rt-otel-init #:rt-otel-set-attribute
                #:rt-otel-set-status #:rt-otel-span #:rt-otel-span-attributes #:rt-otel-span-end #:rt-otel-span-events
                #:rt-otel-span-name #:rt-otel-span-parent-span-id #:rt-otel-span-span-id #:rt-otel-span-start #:rt-otel-span-status-code
                #:rt-otel-span-status-message #:rt-otel-span-to-json #:rt-otel-span-trace-id #:rt-otel-start-span #:rt-register-metric
                #:rt-with-span #:set-default-logger #:with-captured-log-context #:with-default-logger #:with-log-context
                #:with-log-span
                #:*rt-metrics-registry* #:rt-counter-value #:rt-gauge-value #:rt-histogram-buckets
                #:rt-histogram-count #:rt-histogram-counts #:rt-histogram-sum
  )
  (:import-from #:cl-cc/runtime/os
                #:*pending-signals* #:*rt-deopt-enabled* #:*rt-stack-guard-registry* #:*shutdown-hooks* #:*xom-enabled*
                #:+rt-af-inet+ #:+rt-af-inet6+ #:+rt-affinity-mask-bytes+ #:+rt-sighup+ #:+rt-sigint+
                #:+rt-sigterm+ #:+rt-sigusr1+ #:+rt-sigusr2+ #:+rt-sigwinch+ #:+rt-sock-dgram+
                #:+rt-sock-stream+ #:+rt-socket-error+ #:+rt-socket-readable+ #:+rt-socket-writable+ #:cl-cc-call
                #:cl-cc-callback #:cl-cc-cleanup #:cl-cc-error #:cl-cc-error-code #:cl-cc-error-message
                #:cl-cc-error-p #:cl-cc-eval #:cl-cc-init #:cl-cc-last-error #:cl-cc-register-callback
                #:cl-cc-state #:cl-cc-state-callbacks #:cl-cc-state-closed-p #:cl-cc-state-id #:cl-cc-state-last-error
                #:cl-cc-state-p #:cl-cc-state-package #:cl-cc-state-vm #:cl-cc-value #:cl-cc-value-kind
                #:cl-cc-value-p #:cl-cc-value-payload #:detect-cpu-cores #:detect-numa-topology #:get-cpu-affinity-mask
                #:keyboard-interrupt #:make-cl-cc-error #:make-cl-cc-state #:make-cl-cc-value #:make-rt-socket-address
                #:memory-tier-info #:rt-accept #:rt-allocate-code-memory-xom-aware #:rt-allocate-xom-code-memory #:rt-argv
                #:rt-bind #:rt-bootstrap-standalone #:rt-chdir #:rt-clear-output #:rt-clear-signal-handlers
                #:rt-close #:rt-close-file #:rt-close-socket #:rt-connect #:rt-cpu-topology
                #:rt-define-foreign-function #:rt-define-foreign-struct #:rt-delete-file #:rt-directory #:rt-ensure-directories-exist
                #:rt-epoll-create #:rt-epoll-ctl #:rt-epoll-wait #:rt-exec #:rt-exit
                #:rt-ffi-callback-invoke #:rt-ffi-close-library #:rt-ffi-init #:rt-ffi-load-library #:rt-ffi-struct-field-offset
                #:rt-ffi-struct-size #:rt-file-write-date #:rt-finalize-xom-code-memory #:rt-finish-output #:rt-force-output
                #:rt-foreign-funcall #:rt-fork #:rt-format #:rt-fresh-line #:rt-get-internal-real-time
                #:rt-get-internal-run-time #:rt-get-output-stream-string #:rt-get-signal-handler #:rt-get-universal-time #:rt-getcwd
                #:rt-getenv #:rt-gettime-monotonic #:rt-gettime-real #:rt-input-stream-p #:rt-interactive-stream-p
                #:rt-listen #:rt-make-broadcast-stream #:rt-make-concatenated-stream #:rt-make-echo-stream #:rt-make-pathname-native
                #:rt-make-socket-stream #:rt-make-string-output-stream #:rt-make-string-stream #:rt-make-synonym-stream #:rt-make-two-way-stream
                #:rt-merge-pathnames #:rt-namestring #:rt-net-init #:rt-open #:rt-open-file
                #:rt-open-stream-p #:rt-output-stream-p #:rt-pathname-directory #:rt-pathname-name #:rt-pathname-type
                #:rt-pathnamep #:rt-peek-char #:rt-platform #:rt-platform-darwin-p #:rt-platform-linux-p
                #:rt-prin1 #:rt-princ #:rt-print #:rt-probe-file #:rt-process
                #:rt-process-alive-p #:rt-process-error #:rt-process-exit-code #:rt-process-input #:rt-process-kill
                #:rt-process-output #:rt-process-p #:rt-process-pending-signals #:rt-process-pid #:rt-process-status
                #:rt-process-wait #:rt-read #:rt-read-byte #:rt-read-char #:rt-read-line
                #:rt-read-sequence #:rt-release-xom-code-memory #:rt-rename-file #:rt-resolve-address #:rt-run-program
                #:rt-select #:rt-set-nonblocking #:rt-set-signal-handler #:rt-setenv #:rt-shell
                #:rt-signal-mask #:rt-signals-init #:rt-sleep #:rt-socket #:rt-socket-address
                #:rt-socket-address-family #:rt-socket-address-host #:rt-socket-address-port #:rt-socket-entry #:rt-socket-entry-p
                #:rt-socket-name #:rt-socket-recv #:rt-socket-send #:rt-stream-element-type #:rt-stream-write-string
                #:rt-terpri #:rt-thread-get-affinity #:rt-thread-set-affinity #:rt-truename #:rt-unblock-signal
                #:rt-unread-char #:rt-unsetenv #:rt-waitpid #:rt-with-signal-handler #:rt-write
                #:rt-write-byte #:rt-write-char #:rt-write-line #:rt-write-sequence #:rt-write-string
                #:rt-write-to-string #:rt-write-to-string-with-controls #:set-cpu-affinity-mask
                #:%rt-record-pending-signal #:%rt-run-shutdown-hooks #:*rt-sigaction-installed*
                #:*rt-signal-handlers* #:*rt-signal-mask* #:make-rt-signal-handler #:rt-dispatch-os-signal
                #:rt-floating-point-exception #:rt-install-signal-handler #:rt-interrupt #:rt-load
                #:rt-make-pathname #:rt-os-signal #:rt-os-signal-condition #:rt-os-signal-name
                #:rt-remove-signal-handler #:rt-signal-condition-class #:rt-signal-handler-signal
                #:rt-signal-name #:rt-signal-to-condition
  )
  (:import-from #:cl-cc/runtime/profiling
                #:*rt-continuous-profile-session* #:make-rt-continuous-profile-session #:make-rt-profile-frame #:make-rt-profile-sample #:rt-continuous-profile->otel-span
                #:rt-continuous-profile-session #:rt-continuous-profile-session-endpoint #:rt-continuous-profile-session-name #:rt-continuous-profile-session-output #:rt-continuous-profile-session-running-p
                #:rt-continuous-profile-session-sample-log #:rt-continuous-profile-session-sample-rate-hz #:rt-continuous-profile-session-samples #:rt-continuous-profile-session-span-id #:rt-continuous-profile-session-trace-id
                #:rt-continuous-profile-to-otel-json #:rt-continuous-profile-to-pprof-json #:rt-export-continuous-profile #:rt-profile-frame #:rt-profile-frame-address
                #:rt-profile-frame-function #:rt-profile-frame-perf-symbol #:rt-profile-frame-source-file #:rt-profile-frame-source-line #:rt-profile-sample
                #:rt-profile-sample-count #:rt-profile-sample-span-id #:rt-profile-sample-stack #:rt-profile-sample-thread-id #:rt-profile-sample-timestamp-nanos
                #:rt-profile-sample-trace-id #:rt-record-profile-sample #:rt-start-continuous-profile #:rt-stop-continuous-profile #:rt-wait-for-continuous-profile-sample
                #:%rt-profile-collapsed-stack #:%rt-profile-normalize-frame #:%rt-profile-resolve-perf-symbol
                #:%rt-profile-trim-samples #:rt-profile-frame-p
  )
  (:import-from #:cl-cc/runtime/profiling/infra
                #:perf-counters-unsupported #:rdtsc #:rdtscp #:rt-perf-enable-counter #:rt-perf-init
                #:rt-perf-read-counter #:rt-with-perf-counters
                #:*perf-event-names* #:*rt-perf-counters* #:rt-perf-counter-enabled #:rt-perf-counter-name
                #:rt-perf-counter-type #:rt-perf-disable-counter
  )
  (:import-from #:cl-cc/runtime/resilience
                #:rt-make-token-bucket #:rt-token-bucket-acquire #:rt-token-bucket-stats #:rt-token-bucket-wait
                #:rt-token-bucket-accepted #:rt-token-bucket-burst #:rt-token-bucket-dropped
                #:rt-token-bucket-last #:rt-token-bucket-rate #:rt-token-bucket-refill #:rt-token-bucket-tokens
                #:rt-token-bucket-try-acquire
  )
  (:import-from #:cl-cc/runtime/serialization
                #:deserialize #:serialize
  )
  (:import-from #:cl-cc/runtime/values
                #:*compressed-pointers-enabled* #:*heap-base-address* #:*rt-package-registry* #:*rt-string-dedup-table* #:+addr-mask+
                #:+compressed-heap-region-bytes+ #:+compressed-heap-region-words+ #:+compressed-pointer-flag+ #:+compressed-pointer-offset-mask+ #:+fixnum-mask+
                #:+fixnum-shift+ #:+fixnum-tag+ #:+nan-boxing-quiet-nan+ #:+nan-tag-base+ #:+ptr-base+
                #:+ptr-mask+ #:+rt-array-metadata-version+ #:+rt-array-type-tag+ #:+rt-bignum-digit-base+ #:+rt-bignum-type-tag+
                #:+rt-tag-cons+ #:+rt-tag-function+ #:+rt-tag-string+ #:+rt-tag-symbol+ #:+sso-string-base+
                #:+sso-string-mask+ #:+sso-string-max-length+ #:+tag-array+ #:+tag-char+ #:+tag-character+
                #:+tag-cons+ #:+tag-fixnum+ #:+tag-function+ #:+tag-mask+ #:+tag-object+
                #:+tag-other+ #:+tag-string+ #:+tag-symbol+ #:+val-nil+ #:+val-t+
                #:+val-unbound+ #:cl-value->val #:compressed-pointer-enabled-p #:decode-char #:decode-compressed-pointer
                #:decode-double #:decode-fixnum #:decode-pointer #:decode-sso-string #:encode-bool
                #:encode-char #:encode-compressed-pointer #:encode-double #:encode-fixnum #:encode-pointer
                #:encode-sso-string #:make-rt-weak-hash-entry #:pointer-tag #:rt-* #:rt-+
                #:rt-- #:rt-/ #:rt-1+ #:rt-1- #:rt-<
                #:rt-<= #:rt-> #:rt->= #:rt-abs #:rt-acons
                #:rt-acos #:rt-add #:rt-adjust-array #:rt-alpha-char-p #:rt-alphanumericp
                #:rt-append #:rt-aref #:rt-array-adjustable-p #:rt-array-dimension #:rt-array-dimensions
                #:rt-array-displacement #:rt-array-has-fill-pointer-p #:rt-array-length #:rt-array-rank #:rt-array-row-major-index
                #:rt-array-total-size #:rt-aset #:rt-ash #:rt-asin #:rt-assoc
                #:rt-atan #:rt-atan2 #:rt-atomp #:rt-bit-access #:rt-bit-and
                #:rt-bit-not #:rt-bit-or #:rt-bit-set #:rt-bit-xor #:rt-both-case-p
                #:rt-butlast #:rt-car #:rt-cdr #:rt-ceiling #:rt-char
                #:rt-char-code #:rt-char-downcase #:rt-char-equal #:rt-char-equal-ci #:rt-char-equal-cs
                #:rt-char-ge-cs #:rt-char-greaterp-ci #:rt-char-gt-cs #:rt-char-le-cs #:rt-char-lessp-ci
                #:rt-char-lt-cs #:rt-char-name #:rt-char-ne-cs #:rt-char-not-equal-ci #:rt-char-not-greaterp-ci
                #:rt-char-not-lessp-ci #:rt-char-upcase #:rt-char= #:rt-characterp #:rt-cl-and
                #:rt-cl-or #:rt-clrhash #:rt-code-char #:rt-coerce #:rt-coerce-to-list
                #:rt-coerce-to-string #:rt-coerce-to-vector #:rt-complex #:rt-concatenate-seqs #:rt-conjugate
                #:rt-cons #:rt-consp #:rt-copy-list #:rt-copy-tree #:rt-cos
                #:rt-cosh #:rt-dec #:rt-decode-float #:rt-denominator #:rt-digit-char
                #:rt-digit-char-p #:rt-div #:rt-do-all-symbols #:rt-do-external-symbols #:rt-elt
                #:rt-endp #:rt-ensure-values #:rt-eq #:rt-eql #:rt-equal
                #:rt-equal-fn #:rt-equalp #:rt-evenp #:rt-exp #:rt-export
                #:rt-expt #:rt-fboundp #:rt-fceiling #:rt-ffloor #:rt-fifth
                #:rt-fill-pointer #:rt-find-all-symbols #:rt-find-package #:rt-first #:rt-float
                #:rt-float-digits #:rt-float-precision #:rt-float-radix #:rt-float-sign #:rt-floatp
                #:rt-floor #:rt-fourth #:rt-fround #:rt-ftruncate #:rt-gcd
                #:rt-ge #:rt-gensym #:rt-get-global #:rt-get-prop #:rt-gethash
                #:rt-graphic-char-p #:rt-gt #:rt-hash-count #:rt-hash-keys #:rt-hash-rehash-size
                #:rt-hash-rehash-threshold #:rt-hash-size #:rt-hash-table-p #:rt-hash-table-weakness #:rt-hash-test
                #:rt-hash-values #:rt-imagpart #:rt-inc #:rt-integer-decode-float #:rt-integer-length
                #:rt-integerp #:rt-intern #:rt-keywordp #:rt-last #:rt-lcm
                #:rt-le #:rt-length #:rt-list-length #:rt-listp #:rt-logand
                #:rt-logbitp #:rt-logcount #:rt-logeqv #:rt-logior #:rt-lognot
                #:rt-logtest #:rt-logxor #:rt-lower-case-p #:rt-lt #:rt-make-array
                #:rt-make-hash-table #:rt-make-list #:rt-make-package #:rt-make-random-state #:rt-make-string
                #:rt-maphash #:rt-max #:rt-member #:rt-min #:rt-minusp
                #:rt-mod #:rt-mul #:rt-name-char #:rt-native-bignum-add #:rt-native-bignum-allocate
                #:rt-native-bignum-mul #:rt-native-bignum-p #:rt-native-bignum-sub #:rt-native-bignum-to-integer #:rt-native-integer->value
                #:rt-nconc #:rt-neg #:rt-not #:rt-nreverse #:rt-nth
                #:rt-nthcdr #:rt-null #:rt-null-p #:rt-num-eq #:rt-numberp
                #:rt-numerator #:rt-oddp #:rt-package-name #:rt-parse-integer #:rt-phase
                #:rt-pin-unboxed-array #:rt-pinned-array-data-pointer #:rt-pinned-unboxed-array-buffer-array #:rt-pinned-unboxed-array-buffer-length #:rt-pinned-unboxed-array-buffer-p
                #:rt-pinned-unboxed-array-buffer-released-p #:rt-plusp #:rt-pop-list #:rt-push-list #:rt-put-prop
                #:rt-random #:rt-rational #:rt-rationalize #:rt-read-from-string #:rt-read-sexp
                #:rt-realpart #:rt-release-pinned-array #:rt-rem #:rt-remhash #:rt-remprop
                #:rt-rest #:rt-reverse #:rt-round #:rt-row-major-aref #:rt-rplaca
                #:rt-rplacd #:rt-sbit #:rt-scale-float #:rt-search-string #:rt-second
                #:rt-set-fill-pointer #:rt-set-global #:rt-sethash #:rt-shadowing-import #:rt-sin
                #:rt-sinh #:rt-spread-values #:rt-sqrt #:rt-standard-char-p #:rt-string-capitalize
                #:rt-string-coerce #:rt-string-dedup #:rt-string-downcase #:rt-string-equal-ci #:rt-string-greaterp
                #:rt-string-intern #:rt-string-left-trim #:rt-string-length #:rt-string-lessp #:rt-string-not-equal
                #:rt-string-not-greaterp #:rt-string-not-lessp #:rt-string-ref #:rt-string-right-trim #:rt-string-set
                #:rt-string-trim #:rt-string-upcase #:rt-string< #:rt-string<= #:rt-string=
                #:rt-string> #:rt-string>= #:rt-stringp #:rt-sub #:rt-subseq
                #:rt-subst #:rt-svref #:rt-svset #:rt-symbol-name #:rt-symbol-plist
                #:rt-symbolp #:rt-tag-bits #:rt-tag-fixnum #:rt-tan #:rt-tanh
                #:rt-third #:rt-truncate #:rt-type-of #:rt-typep #:rt-unexport
                #:rt-untag-fixnum #:rt-unuse-package #:rt-upper-case-p #:rt-use-package #:rt-values-clear
                #:rt-values-count #:rt-values-push #:rt-values-ref #:rt-values-to-list #:rt-vector-pop
                #:rt-vector-push #:rt-vector-push-extend #:rt-vectorp #:rt-weak-hash-entry #:rt-weak-hash-table
                #:rt-weak-hash-table-p #:rt-zerop #:rtwhe-key #:rtwhe-key-ephemeron #:rtwhe-value
                #:rtwhe-value-ephemeron #:val->cl-value #:val-char-p #:val-compressed-pointer-p #:val-cons-p
                #:val-double-p #:val-fixnum-p #:val-function-p #:val-nil-p #:val-object-p
                #:val-pointer-p #:val-sso-string-p #:val-string-p #:val-symbol-p #:val-t-p
                #:val-unbound-p
                #:%rt-bootstrap-package-registry #:*rt-weak-hash-table-registry* #:rt-find-symbol #:rt-import
                #:rt-package-nicknames #:val-immediate-symbol-p
  )
  (:export
   #:%rt-gc-work-stealing-drain #:%rt-phantom-ref-referent #:*compacting-gc-enabled* #:*compressed-pointers-enabled* #:*concurrent-gc-enabled*
   #:*default-logger* #:*frame-pool* #:*frame-pool-top* #:*gc-allocation-rate-limit-words-per-sec* #:*gc-back-pressure-threshold*
   #:*gc-compact-after-major-cycles* #:*gc-epsilon-enabled* #:*gc-inhibit-during-signals* #:*gc-nursery-size* #:*gc-old-size-words*
   #:*gc-pacer-enabled* #:*gc-pause-target-ms* #:*gc-pending* #:*gc-probes-enabled* #:*gc-profile-enabled*
   #:*gc-profile-interval* #:*gc-regions* #:*gc-stress-mode* #:*gc-tenuring-threshold* #:*gc-threads*
   #:*gc-verify-after-collect* #:*gc-worker-count* #:*gc-young-size-words* #:*handler-stack* #:*heap-base-address*
   #:*large-object-threshold* #:*pending-finalizers* #:*pending-signals* #:*restart-stack* #:*rt-asan-enabled*
   #:*rt-class-registry* #:*rt-code-cache* #:*rt-concurrent-gc-enabled-p* #:*rt-concurrent-gc-mutator-assist-p* #:*rt-concurrent-gc-stw-phases*
   #:*rt-concurrent-gc-write-barrier-mode* #:*rt-continuous-profile-session* #:*rt-current-pinning-heap* #:*rt-debugger-hook* #:*rt-default-reference-queue*
   #:*rt-deopt-enabled* #:*rt-dl-enabled* #:*rt-dl-thread-locks* #:*rt-dl-thread-waits* #:*rt-ephemeron-registry*
   #:*rt-finalization-queue* #:*rt-finalizer-registry* #:*rt-fork-join-pool* #:*rt-gc-alloc-hooks* #:*rt-gc-death-hooks*
   #:*rt-gc-safe-region-depths* #:*rt-generic-function-registry* #:*rt-handler-stack* #:*rt-hwasan-enabled* #:*rt-immortal-registry*
   #:*rt-logger* #:*rt-msan-enabled* #:*rt-native-thread-registry* #:*rt-numa-enabled* #:*rt-otel-span*
   #:*rt-package-registry* #:*rt-reference-registry* #:*rt-region-mixed-collection-enabled-p* #:*rt-stack-guard-registry* #:*rt-string-dedup-table*
   #:*rt-tsan-enabled* #:*rt-tsan-thread-id* #:*rt-ubsan-enabled* #:*rt-use-barrier-batching* #:*rt-work-stealing-scheduler*
   #:*satb-queue* #:*saved-core-pathname* #:*shutdown-hooks* #:*use-huge-pages* #:*write-barrier-opt-enabled*
   #:*xom-enabled* #:+addr-mask+ #:+compressed-heap-region-bytes+ #:+compressed-heap-region-words+ #:+compressed-pointer-flag+
   #:+compressed-pointer-offset-mask+ #:+fixnum-mask+ #:+fixnum-shift+ #:+fixnum-tag+ #:+frame-arg-end+
   #:+frame-arg-start+ #:+frame-callee-save-end+ #:+frame-callee-save-start+ #:+frame-caller-save-end+ #:+frame-caller-save-start+
   #:+frame-pool-size+ #:+frame-register-count+ #:+frame-return-reg+ #:+frame-spill-start+ #:+gc-card-size-words+
   #:+gc-region-size+ #:+level-debug+ #:+level-error+ #:+level-fatal+ #:+level-info+
   #:+level-warn+ #:+nan-boxing-quiet-nan+ #:+nan-tag-base+ #:+ptr-base+ #:+ptr-mask+
   #:+rt-af-inet+ #:+rt-af-inet6+
   #:+rt-affinity-mask-bytes+ #:+rt-array-metadata-version+ #:+rt-array-type-tag+ #:+rt-bignum-digit-base+ #:+rt-bignum-type-tag+
   #:+rt-map-fixed+ #:+rt-prot-none+ #:+rt-sighup+ #:+rt-sigint+ #:+rt-sigterm+
   #:+rt-sigusr1+ #:+rt-sigusr2+ #:+rt-sigwinch+ #:+rt-sock-dgram+ #:+rt-sock-stream+
   #:+rt-socket-error+ #:+rt-socket-readable+ #:+rt-socket-writable+ #:+rt-tag-cons+ #:+rt-tag-function+
   #:+rt-tag-string+ #:+rt-tag-symbol+ #:+sso-string-base+ #:+sso-string-mask+ #:+sso-string-max-length+
   #:+tag-array+ #:+tag-char+ #:+tag-character+ #:+tag-cons+ #:+tag-fixnum+
   #:+tag-function+ #:+tag-mask+ #:+tag-object+ #:+tag-other+ #:+tag-string+
   #:+tag-symbol+ #:+val-nil+ #:+val-t+ #:+val-unbound+ #:arena-alloc
   #:arena-reset #:call-with-captured-log-context #:capture-log-context #:cl-cc-call #:cl-cc-callback
   #:cl-cc-cleanup #:cl-cc-error #:cl-cc-error-code #:cl-cc-error-message #:cl-cc-error-p
   #:cl-cc-eval #:cl-cc-init #:cl-cc-last-error #:cl-cc-register-callback #:cl-cc-state
   #:cl-cc-state-callbacks #:cl-cc-state-closed-p #:cl-cc-state-id #:cl-cc-state-last-error #:cl-cc-state-p
   #:cl-cc-state-package #:cl-cc-state-vm #:cl-cc-value #:cl-cc-value-kind #:cl-cc-value-p
   #:cl-cc-value-payload #:cl-value->val #:colored-pointer-p #:compressed-pointer-enabled-p #:concurrent-mark-worker
   #:decode-char #:decode-compressed-pointer #:decode-double #:decode-fixnum #:decode-pointer
   #:decode-sso-string #:derive-logger #:deserialize #:detect-cpu-cores #:detect-numa-topology
   #:enable-epsilon-gc #:encode-bool #:encode-char #:encode-compressed-pointer #:encode-double
   #:encode-fixnum #:encode-pointer #:encode-sso-string #:epsilon-gc-enabled-p #:estimate-region-garbage-ratio
   #:frame-pool-acquire #:frame-pool-release #:frame-reg-get #:frame-reg-set #:frame-reset
   #:gc-region #:gc-stats #:get-cpu-affinity-mask #:header-clear-finalized #:header-clear-gray
   #:header-clear-mark #:header-finalized-p #:header-forwarding-p #:header-forwarding-ptr #:header-gray-p
   #:header-make-forwarding-ptr #:header-marked-p #:header-set-finalized #:header-set-gray #:header-set-mark
   #:huge-pages-enabled-p #:initialize-frame-pool #:keyboard-interrupt #:log-condition #:log-context-snapshot-p
   #:log-debug #:log-default-debug #:log-default-error #:log-default-fatal #:log-default-info
   #:log-default-warn #:log-error #:log-fatal #:log-info #:log-record-fields
   #:log-warn #:logger-child #:logger-with #:make-arena #:make-cl-cc-error
   #:make-cl-cc-state #:make-cl-cc-value #:make-function-handler #:make-gc-region #:make-json-handler
   #:make-logger #:make-object-pool #:make-rt-continuous-profile-session #:make-rt-effect #:make-rt-ephemeron
   #:make-rt-handler #:make-rt-handler-state #:make-rt-header #:make-rt-heap #:make-rt-otel-event
   #:make-rt-otel-span #:make-rt-profile-frame #:make-rt-profile-sample #:make-rt-restart
   #:make-rt-socket-address #:make-rt-stackmap #:make-rt-tlab #:make-rt-weak-hash-entry #:make-text-handler
   #:memory-tier-info #:mmap-advice #:mmap-array #:mmap-close #:mmap-file
   #:mmap-sync #:opt-pass-stm #:perf-counters-unsupported #:pointer-color #:pointer-tag
   #:pool-acquire #:pool-release #:prometheus-text-format #:rdtsc #:rdtscp
   #:register-finalizer #:rt-* #:rt-+ #:rt-- #:rt-/
   #:rt-1+ #:rt-1- #:rt-< #:rt-<= #:rt->
   #:rt->= #:rt-abs #:rt-accept #:rt-acons #:rt-acos
   #:rt-actor-receive #:rt-actor-send #:rt-add #:rt-adjust-array #:rt-all-threads
   #:rt-alloc #:rt-alloc-call-frame #:rt-allocate-anonymous-memory #:rt-allocate-code-memory #:rt-allocate-code-memory-xom-aware
   #:rt-allocate-xom-code-memory #:rt-allocator-init #:rt-alpha-char-p #:rt-alphanumericp #:rt-append
   #:rt-apply-fn #:rt-aref #:rt-arena #:rt-arena-block #:rt-arena-block-offset
   #:rt-arena-cursor #:rt-argv #:rt-arithmetic-error #:rt-array-adjustable-p #:rt-array-dimension
   #:rt-array-dimensions #:rt-array-displacement #:rt-array-has-fill-pointer-p #:rt-array-length #:rt-array-rank
   #:rt-array-row-major-index #:rt-array-total-size #:rt-aset #:rt-ash #:rt-asin
   #:rt-assoc #:rt-async #:rt-async-channel #:rt-async-cps #:rt-async-cps-transform
   #:rt-async-defun #:rt-async-lambda #:rt-async-recv #:rt-async-send #:rt-async-submit
   #:rt-atan #:rt-atan2 #:rt-atomically #:rt-atomp #:rt-await
   #:rt-await* #:rt-barrier-reset #:rt-barrier-wait #:rt-base64-decode #:rt-base64-encode
   #:rt-bind #:rt-bit-access #:rt-bit-and #:rt-bit-not #:rt-bit-or
   #:rt-bit-set #:rt-bit-xor #:rt-bootstrap-standalone #:rt-both-case-p #:rt-boundp
   #:rt-butlast #:rt-call-fn #:rt-call-generic #:rt-call-next-method #:rt-capture-image-state
   #:rt-car #:rt-card-clear #:rt-card-clear-all #:rt-card-dirty-p #:rt-card-index
   #:rt-card-mark-dirty #:rt-card-summary-clean-block-p #:rt-card-summary-update #:rt-cdr #:rt-ceiling
   #:rt-cell-error #:rt-cerror #:rt-channel-close #:rt-channel-recv #:rt-channel-select
   #:rt-channel-send #:rt-channel-try-recv #:rt-channel-try-send #:rt-char #:rt-char-code
   #:rt-char-downcase #:rt-char-equal #:rt-char-equal-ci #:rt-char-equal-cs #:rt-char-ge-cs
   #:rt-char-greaterp-ci #:rt-char-gt-cs #:rt-char-le-cs #:rt-char-lessp-ci #:rt-char-lt-cs
   #:rt-char-name #:rt-char-ne-cs #:rt-char-not-equal-ci #:rt-char-not-greaterp-ci #:rt-char-not-lessp-ci
   #:rt-char-upcase #:rt-char= #:rt-characterp #:rt-chdir #:rt-check-stack-overflow
   #:rt-cl-and #:rt-cl-or #:rt-class-name #:rt-class-of #:rt-clear-output
   #:rt-clear-signal-handlers #:rt-close #:rt-close-file #:rt-close-region #:rt-close-socket
   #:rt-closure-ref #:rt-clrhash #:rt-code-cache-evict #:rt-code-cache-lookup #:rt-code-cache-stats
   #:rt-code-cache-store #:rt-code-char #:rt-coerce #:rt-coerce-to-list #:rt-coerce-to-string
   #:rt-coerce-to-vector #:rt-complex #:rt-compress-object-ref #:rt-compress-stackmap-slots #:rt-compute-applicable-methods
   #:rt-concatenate-seqs #:rt-condition-notify #:rt-condition-notify-all #:rt-condition-wait #:rt-condition-wait-until
   #:rt-conjugate #:rt-connect #:rt-cons #:rt-consp
   #:rt-context-cancel #:rt-context-cancelled-p #:rt-context-get-deadline #:rt-context-spawn #:rt-context-value
   #:rt-continuous-profile->otel-span #:rt-continuous-profile-session #:rt-continuous-profile-session-endpoint #:rt-continuous-profile-session-name #:rt-continuous-profile-session-output
   #:rt-continuous-profile-session-running-p #:rt-continuous-profile-session-sample-log #:rt-continuous-profile-session-sample-rate-hz #:rt-continuous-profile-session-samples #:rt-continuous-profile-session-span-id
   #:rt-continuous-profile-session-trace-id #:rt-continuous-profile-to-otel-json #:rt-continuous-profile-to-pprof-json #:rt-control-error #:rt-copy-list
   #:rt-copy-tree #:rt-cos #:rt-cosh #:rt-counter-increment! #:rt-cpu-topology
   #:rt-current-handler #:rt-current-thread #:rt-current-thread-id #:rt-deadlock-after-lock
   #:rt-deadlock-after-unlock #:rt-deadlock-before-lock #:rt-deadlock-detect #:rt-deadlock-init #:rt-dec
   #:rt-decode-float #:rt-decompress-object-ref #:rt-decompress-stackmap-slots #:rt-defclass #:rt-define-foreign-function
   #:rt-define-foreign-struct #:rt-delete-file #:rt-denominator #:rt-destroy-thread #:rt-digit-char
   #:rt-digit-char-p #:rt-directory #:rt-dispatch-restart #:rt-dispatch-signal #:rt-div
   #:rt-division-by-zero #:rt-do-all-symbols #:rt-do-external-symbols #:rt-ebr-collect #:rt-ebr-current-local
   #:rt-ebr-enter #:rt-ebr-init #:rt-ebr-leave #:rt-ebr-register-thread #:rt-ebr-retire
   #:rt-ebr-unregister-thread #:rt-effect #:rt-effect-error #:rt-effect-name #:rt-effect-p
   #:rt-effect-payload #:rt-effect-read #:rt-effect-state #:rt-effect-write #:rt-elt
   #:rt-emit-gc-safepoint #:rt-endp #:rt-ensure-directories-exist #:rt-ensure-values #:rt-ephemeron
   #:rt-ephemeron-key #:rt-ephemeron-value #:rt-epoll-create #:rt-epoll-ctl #:rt-epoll-wait
   #:rt-eq #:rt-eql #:rt-equal #:rt-equal-fn #:rt-equalp
   #:rt-establish-handler #:rt-establish-restart #:rt-evenp #:rt-exec #:rt-exit
   #:rt-exp #:rt-export #:rt-export-continuous-profile #:rt-expt #:rt-fboundp
   #:rt-fceiling #:rt-ffi-callback-invoke #:rt-ffi-close-library #:rt-ffi-init #:rt-ffi-load-library
   #:rt-ffi-struct-field-offset #:rt-ffi-struct-size #:rt-ffloor #:rt-fiber #:rt-fiber-async
   #:rt-fiber-await #:rt-fiber-block #:rt-fiber-done-p #:rt-fiber-local #:rt-fiber-p
   #:rt-fiber-resume #:rt-fiber-schedule #:rt-fiber-spawn #:rt-fiber-status-failed-p #:rt-fiber-yield
   #:rt-fifth #:rt-file-error #:rt-file-write-date #:rt-fill-pointer #:rt-finalize-xom-code-memory
   #:rt-find-all-symbols #:rt-find-class #:rt-find-handler #:rt-find-package #:rt-find-restart
   #:rt-finish-output #:rt-first #:rt-float #:rt-float-digits #:rt-float-precision
   #:rt-float-radix #:rt-float-sign #:rt-floating-point-overflow #:rt-floating-point-underflow #:rt-floatp
   #:rt-floor #:rt-force-output #:rt-foreign-funcall #:rt-fork #:rt-format
   #:rt-fourth #:rt-free #:rt-free-call-frame #:rt-fresh-line #:rt-fround
   #:rt-ftruncate #:rt-functionp #:rt-future-await #:rt-future-done-p #:rt-future-resolve
   #:rt-future-then #:rt-gauge-set! #:rt-gc-add-root #:rt-gc-add-root-typed #:rt-gc-alloc
   #:rt-gc-clear-stack-allocated-objects #:rt-gc-compact-old-space #:rt-gc-concurrent-assist #:rt-gc-concurrent-sweep #:rt-gc-concurrent-sweep-worker
   #:rt-gc-configure-concurrent-mode #:rt-gc-current-cycle #:rt-gc-detect-worker-count #:rt-gc-drain-satb-thread-queues #:rt-gc-dynamic-tenure
   #:rt-gc-enter-safe-region #:rt-gc-flush-barrier-buffer #:rt-gc-generate-stackmap-stub #:rt-gc-heap-census #:rt-gc-heap-dump-dot
   #:rt-gc-heap-snapshot #:rt-gc-inhibit-p #:rt-gc-leave-safe-region #:rt-gc-major-collect #:rt-gc-map-heap-objects
   #:rt-gc-map-section-documentation #:rt-gc-minor-collect #:rt-gc-numa-affinity #:rt-gc-pacer-maybe-throttle #:rt-gc-parallel-mark
   #:rt-gc-parallel-root-scan #:rt-gc-parallel-sweep #:rt-gc-pressure-warning #:rt-gc-probe-alloc #:rt-gc-probe-gc-end
   #:rt-gc-probe-gc-start #:rt-gc-process-references #:rt-gc-profile-report #:rt-gc-profile-sample #:rt-gc-region-handle-evacuation-failure
   #:rt-gc-region-mixed-collect #:rt-gc-region-select-mixed #:rt-gc-register-alloc-hook #:rt-gc-register-death-hook #:rt-gc-register-stack-allocated-object
   #:rt-gc-register-stackmap #:rt-gc-register-thread #:rt-gc-remove-root #:rt-gc-request #:rt-gc-safepoint-check
   #:rt-gc-satb-enqueue #:rt-gc-scan-stackmaps #:rt-gc-select-policy #:rt-gc-should-run-compaction-p #:rt-gc-simd-zero-fill
   #:rt-gc-stack-allocated-object-p #:rt-gc-stats #:rt-gc-tlab-alloc #:rt-gc-tlab-retire-all #:rt-gc-unload-code
   #:rt-gc-unregister-thread #:rt-gc-verify-heap #:rt-gc-verify-tri-color-invariant #:rt-gc-write-barrier #:rt-gcd
   #:rt-ge #:rt-gensym
   #:rt-get-global #:rt-get-internal-real-time #:rt-get-internal-run-time #:rt-get-output-stream-string #:rt-get-prop
   #:rt-get-signal-handler #:rt-get-universal-time #:rt-getcwd #:rt-getenv #:rt-gethash
   #:rt-gettime-monotonic #:rt-gettime-real #:rt-graphic-char-p #:rt-green-thread #:rt-green-thread-error
   #:rt-green-thread-p #:rt-green-thread-result #:rt-green-thread-spawn #:rt-green-thread-status #:rt-gt
   #:rt-handle #:rt-handler #:rt-handler-condition-type #:rt-handler-handler-function #:rt-handler-p
   #:rt-handler-state #:rt-handler-state-handlers #:rt-handler-state-p #:rt-hash-count #:rt-hash-keys
   #:rt-hash-rehash-size #:rt-hash-rehash-threshold #:rt-hash-size #:rt-hash-table-p #:rt-hash-table-weakness
   #:rt-hash-test #:rt-hash-values #:rt-header-age #:rt-header-gc-bits #:rt-header-increment-age
   #:rt-header-shape-id #:rt-header-size #:rt-header-type-tag #:rt-heap #:rt-heap-addr-p
   #:rt-heap-age-hist #:rt-heap-barrier-buffer #:rt-heap-card-summary #:rt-heap-card-table #:rt-heap-compaction-trigger-fraction
   #:rt-heap-fragmentation-pct #:rt-heap-free-list #:rt-heap-gc-inhibit #:rt-heap-gc-pause-max #:rt-heap-gc-pause-total
   #:rt-heap-gc-pending #:rt-heap-gc-state #:rt-heap-initialize-regions #:rt-heap-interleave #:rt-heap-large-obj-base
   #:rt-heap-large-obj-free #:rt-heap-large-obj-size #:rt-heap-large-obj-threshold #:rt-heap-major-gc-count #:rt-heap-max-heap-words
   #:rt-heap-maybe-grow #:rt-heap-maybe-shrink #:rt-heap-minor-gc-count #:rt-heap-num-cards #:rt-heap-object-header
   #:rt-heap-object-size #:rt-heap-occupancy-pct #:rt-heap-old-base #:rt-heap-old-free #:rt-heap-old-size
   #:rt-heap-pressure-hooks #:rt-heap-pressure-threshold-high #:rt-heap-pressure-threshold-low #:rt-heap-randomize-base #:rt-heap-ref
   #:rt-heap-region #:rt-heap-region-for-address #:rt-heap-region-size-words #:rt-heap-regions #:rt-heap-register-pressure-hook
   #:rt-heap-roots #:rt-heap-satb-queue #:rt-heap-set #:rt-heap-set-header #:rt-heap-should-compact-p
   #:rt-heap-shrink-threshold #:rt-heap-total-alloc-words #:rt-heap-words #:rt-heap-words-collected #:rt-heap-words-promoted
   #:rt-heap-young-free #:rt-heap-young-from-base #:rt-heap-young-semi-size #:rt-heap-young-to-base #:rt-histogram-observe!
   #:rt-hmac-sha256 #:rt-hot-reload #:rt-hp-all-protected #:rt-hp-clear #:rt-hp-clear-all
   #:rt-hp-init #:rt-hp-protect #:rt-hp-reclaim #:rt-hp-register-thread #:rt-hp-retire
   #:rt-hp-retire-object #:rt-hp-scan #:rt-hp-set-threshold #:rt-hp-unregister-thread #:rt-huge-page-mmap
   #:rt-image-init #:rt-image-register-global #:rt-image-register-restore-hook #:rt-imagpart #:rt-immortal-objects-count
   #:rt-immortal-p #:rt-inc #:rt-input-stream-p #:rt-install-stack-guard #:rt-integer-decode-float
   #:rt-integer-length #:rt-integerp #:rt-interactive-stream-p #:rt-intern #:rt-interrupt-thread
   #:rt-invoke-debugger-hook #:rt-invoke-restart #:rt-keywordp #:rt-large-object-size-p #:rt-last
   #:rt-lcm #:rt-le #:rt-length #:rt-lfhash-cas #:rt-lfhash-count
   #:rt-lfhash-get #:rt-lfhash-remove #:rt-lfqueue-empty-p #:rt-lfqueue-pop #:rt-lfqueue-push
   #:rt-lfstack-empty-p #:rt-lfstack-pop #:rt-lfstack-push #:rt-list-length #:rt-listen
   #:rt-listp #:rt-load-core #:rt-load-image #:rt-lock #:rt-lockfree-init
   #:rt-log #:rt-logand #:rt-logbitp #:rt-logcount #:rt-logeqv
   #:rt-logior #:rt-lognot #:rt-logtest #:rt-logxor #:rt-los-alloc
   #:rt-lower-case-p #:rt-lt #:rt-make-actor
   #:rt-make-array #:rt-make-barrier #:rt-make-broadcast-stream #:rt-make-channel #:rt-make-closure
   #:rt-make-concatenated-stream #:rt-make-condition-variable #:rt-make-counter #:rt-make-echo-stream #:rt-make-ephemeron
   #:rt-make-fiber #:rt-make-future #:rt-make-gauge #:rt-make-hash-table
   #:rt-make-histogram #:rt-make-immortal #:rt-make-instance #:rt-make-instance-0 #:rt-make-lfhash-map
   #:rt-make-lfqueue #:rt-make-lfstack #:rt-make-list #:rt-make-lock #:rt-make-mutex #:rt-make-once #:rt-make-package #:rt-make-pathname-native #:rt-make-phantom-ref
   #:rt-make-random-state #:rt-make-recursive-mutex
   #:rt-make-region #:rt-make-rwlock #:rt-make-scheduler #:rt-make-semaphore #:rt-make-socket-stream
   #:rt-make-soft-ref #:rt-make-spsc-queue #:rt-make-string #:rt-make-string-output-stream #:rt-make-string-stream
   #:rt-make-symbol #:rt-make-synonym-stream #:rt-make-thread #:rt-make-token-bucket #:rt-make-tvar
   #:rt-make-two-way-stream #:rt-make-weak-pointer #:rt-make-weak-ref #:rt-make-work-stealing-scheduler #:rt-makunbound
   #:rt-maphash #:rt-max #:rt-member #:rt-merge-pathnames #:rt-metrics-format-prometheus
   #:rt-min #:rt-minusp #:rt-mmap-init #:rt-mmap-raw #:rt-mmap-ref
   #:rt-mmap-region #:rt-mmap-region-address #:rt-mmap-region-length #:rt-mmap-region-p #:rt-mmap-region-released-p
   #:rt-mmap-set #:rt-mod #:rt-mprotect #:rt-mul #:rt-munmap-raw
   #:rt-mutex-lock #:rt-mutex-owner #:rt-mutex-try-lock #:rt-mutex-unlock #:rt-name-char
   #:rt-namestring #:rt-native-bignum-add #:rt-native-bignum-allocate #:rt-native-bignum-mul #:rt-native-bignum-p
   #:rt-native-bignum-sub #:rt-native-bignum-to-integer #:rt-native-integer->value #:rt-native-thread #:rt-native-thread-p
   #:rt-nconc #:rt-neg #:rt-net-init #:rt-next-method-p #:rt-not
   #:rt-nreverse #:rt-nth #:rt-nthcdr #:rt-null #:rt-null-p
   #:rt-num-eq #:rt-numa-local-alloc #:rt-numa-node-of-thread #:rt-numberp #:rt-numerator
   #:rt-object-pinned-p #:rt-object-pointer-slots #:rt-object-pool #:rt-oddp #:rt-old-addr-p
   #:rt-once-call #:rt-oom-condition #:rt-open #:rt-open-file #:rt-open-stream-p
   #:rt-otel-add-event #:rt-otel-end-span #:rt-otel-event #:rt-otel-event-attributes #:rt-otel-event-name
   #:rt-otel-event-time #:rt-otel-init #:rt-otel-set-attribute #:rt-otel-set-status #:rt-otel-span
   #:rt-otel-span-attributes #:rt-otel-span-end #:rt-otel-span-events #:rt-otel-span-name #:rt-otel-span-parent-span-id
   #:rt-otel-span-span-id #:rt-otel-span-start #:rt-otel-span-status-code #:rt-otel-span-status-message #:rt-otel-span-to-json
   #:rt-otel-span-trace-id #:rt-otel-start-span #:rt-output-stream-p #:rt-package-name #:rt-parallel-algo-init
   #:rt-parallel-for #:rt-parallel-map #:rt-parallel-prefix-scan #:rt-parallel-reduce #:rt-parallel-sort
   #:rt-parse-integer #:rt-pathname-directory #:rt-pathname-name #:rt-pathname-type #:rt-pathnamep
   #:rt-peek-char #:rt-perf-enable-counter #:rt-perf-init #:rt-perf-read-counter #:rt-perform
   #:rt-phantom-ref #:rt-phase #:rt-pin-object #:rt-pin-unboxed-array #:rt-pinned-array-data-pointer
   #:rt-pinned-unboxed-array-buffer-array #:rt-pinned-unboxed-array-buffer-length #:rt-pinned-unboxed-array-buffer-p #:rt-pinned-unboxed-array-buffer-released-p #:rt-platform
   #:rt-platform-darwin-p #:rt-platform-linux-p #:rt-plusp #:rt-poison-return-address #:rt-pop-handler #:rt-pop-list #:rt-pop-restart
   #:rt-prin1 #:rt-princ #:rt-print #:rt-probe-file #:rt-process
   #:rt-process-alive-p #:rt-process-error #:rt-process-exit-code #:rt-process-input #:rt-process-kill
   #:rt-process-output #:rt-process-p #:rt-process-pending-signals #:rt-process-pid #:rt-process-status
   #:rt-process-wait #:rt-profile-frame #:rt-profile-frame-address #:rt-profile-frame-function #:rt-profile-frame-perf-symbol
   #:rt-profile-frame-source-file #:rt-profile-frame-source-line #:rt-profile-sample #:rt-profile-sample-count #:rt-profile-sample-span-id
   #:rt-profile-sample-stack #:rt-profile-sample-thread-id #:rt-profile-sample-timestamp-nanos #:rt-profile-sample-trace-id #:rt-program-error
   #:rt-push-handler #:rt-push-list #:rt-push-restart #:rt-put-prop #:rt-qsbr-init
   #:rt-qsbr-quiescent #:rt-qsbr-register-thread #:rt-qsbr-retire #:rt-qsbr-synchronize #:rt-qsbr-thread-count
   #:rt-qsbr-unregister-thread #:rt-random
   #:rt-rational #:rt-rationalize #:rt-rcu-assign-pointer #:rt-rcu-call #:rt-rcu-dereference
   #:rt-rcu-init #:rt-rcu-read-lock #:rt-rcu-synchronize #:rt-read #:rt-read-byte
   #:rt-read-char #:rt-read-from-string #:rt-read-line #:rt-read-sequence #:rt-read-sexp
   #:rt-read-tvar #:rt-realpart #:rt-record-profile-sample #:rt-recursive-mutex-try-lock #:rt-ref-clear-p
   #:rt-ref-get #:rt-reference-queue-process #:rt-region-active-p #:rt-region-alloc #:rt-region-capacity
   #:rt-region-deref #:rt-region-ref-valid-p #:rt-region-used #:rt-register-function #:rt-register-method
   #:rt-register-metric #:rt-release-code-memory #:rt-release-pinned-array #:rt-release-xom-code-memory #:rt-rem
   #:rt-remhash #:rt-remprop #:rt-rename-file #:rt-resolve-address #:rt-resource-limit
   #:rt-rest #:rt-restart #:rt-restart-bind #:rt-restart-case #:rt-restart-function
   #:rt-restart-name #:rt-restart-p #:rt-restore-image-state #:rt-resume #:rt-retry
   #:rt-return-address-poisoned-p #:rt-reverse #:rt-round #:rt-row-major-aref #:rt-rplaca
   #:rt-rplacd #:rt-run-fibers #:rt-run-green-threads #:rt-run-pending-finalizers #:rt-run-program
   #:rt-runtime-condition #:rt-runtime-error #:rt-rwlock-try-read-lock #:rt-rwlock-try-write-lock #:rt-sanitizer-poison-address
   #:rt-sanitizer-reset-state #:rt-sanitizer-set-address-tag #:rt-sanitizer-unpoison-address #:rt-save-core #:rt-save-image
   #:rt-sbit #:rt-scale-float #:rt-scheduler-init #:rt-scheduler-run #:rt-scheduler-steal
   #:rt-search-string #:rt-second #:rt-select #:rt-semaphore-signal #:rt-semaphore-try-wait
   #:rt-semaphore-wait #:rt-serious-condition #:rt-set-fill-pointer #:rt-set-global #:rt-set-nonblocking
   #:rt-set-resource-limit #:rt-set-signal-handler #:rt-set-symbol-value #:rt-setenv #:rt-sethash
   #:rt-sha256 #:rt-sha256-string #:rt-sha512 #:rt-shadowing-import #:rt-shell
   #:rt-signal #:rt-signal-error #:rt-signal-mask #:rt-signals-init #:rt-simple-type-error
   #:rt-sin #:rt-sinh #:rt-size-class-for #:rt-sleep #:rt-sleep-task
   #:rt-slot-boundp #:rt-slot-exists-p #:rt-slot-makunbound #:rt-slot-set #:rt-slot-value
   #:rt-socket #:rt-socket-address #:rt-socket-address-family #:rt-socket-address-host #:rt-socket-address-port
   #:rt-socket-entry #:rt-socket-entry-p #:rt-socket-name #:rt-socket-recv #:rt-socket-send
   #:rt-soft-ref #:rt-soft-ref-referent #:rt-spawn #:rt-spread-values #:rt-spsc-capacity
   #:rt-spsc-empty-p #:rt-spsc-full-p #:rt-spsc-init #:rt-spsc-pop #:rt-spsc-push
   #:rt-spsc-reset #:rt-spsc-size #:rt-spsc-try-pop #:rt-spsc-try-push #:rt-sqrt
   #:rt-stackmap #:rt-stackmap-slots #:rt-standard-char-p #:rt-start-continuous-profile #:rt-stm-conflict
   #:rt-stm-current-cache-hits #:rt-stm-current-effects #:rt-stm-retry #:rt-stm-transaction #:rt-stop-continuous-profile
   #:rt-storage-condition #:rt-stream-element-type #:rt-stream-error #:rt-stream-write-string #:rt-string-capitalize
   #:rt-string-coerce #:rt-string-dedup #:rt-string-downcase #:rt-string-equal-ci #:rt-string-greaterp
   #:rt-string-intern #:rt-string-left-trim #:rt-string-length #:rt-string-lessp #:rt-string-not-equal
   #:rt-string-not-greaterp #:rt-string-not-lessp #:rt-string-ref #:rt-string-right-trim #:rt-string-set
   #:rt-string-trim #:rt-string-upcase #:rt-string< #:rt-string<= #:rt-string=
   #:rt-string> #:rt-string>= #:rt-stringp #:rt-sub #:rt-subseq
   #:rt-subst #:rt-svref #:rt-svset #:rt-symbol-name #:rt-symbol-plist
   #:rt-symbol-value #:rt-symbolp #:rt-sync-init #:rt-tag-bits #:rt-tag-fixnum
   #:rt-tan #:rt-tanh #:rt-terpri #:rt-third #:rt-thread-alive-p
   #:rt-thread-get-affinity #:rt-thread-join #:rt-thread-name #:rt-thread-set-affinity #:rt-thread-yield
   #:rt-tlab #:rt-tlab-base #:rt-tlab-free #:rt-tlab-limit #:rt-tlab-p
   #:rt-tlab-retired-p #:rt-tlab-thread-id #:rt-tlab-waste-bytes #:rt-token-bucket-acquire #:rt-token-bucket-stats
   #:rt-token-bucket-wait #:rt-truename #:rt-truncate #:rt-try-lock #:rt-tvar
   #:rt-tvar-p #:rt-tvar-value-unsafe #:rt-tvar-version-unsafe #:rt-type-error #:rt-type-of
   #:rt-typep #:rt-unblock-signal #:rt-unbound-variable #:rt-undefined-function #:rt-unexport
   #:rt-unlock #:rt-unpin-object #:rt-unpoison-return-address #:rt-unread-char #:rt-unsetenv
   #:rt-untag-fixnum #:rt-unuse-package #:rt-upper-case-p #:rt-use-package #:rt-values-clear
   #:rt-values-count #:rt-values-push #:rt-values-ref #:rt-values-to-list #:rt-vector-pop
   #:rt-vector-push #:rt-vector-push-extend #:rt-vectorp #:rt-wait-for-continuous-profile-sample #:rt-waitpid
   #:rt-warn-fn #:rt-warning #:rt-weak-hash-entry #:rt-weak-hash-table #:rt-weak-hash-table-p
   #:rt-weak-pointer-p #:rt-weak-pointer-value #:rt-weak-ref #:rt-weak-ref-referent #:rt-with-call-stack-guard
   #:rt-with-context #:rt-with-context-value #:rt-with-debugger-hook #:rt-with-dynamic-binding #:rt-with-ebr-critical
   #:rt-with-handler #:rt-with-lock #:rt-with-mutex #:rt-with-perf-counters #:rt-with-rcu-read
   #:rt-with-read-lock #:rt-with-recursive-mutex #:rt-with-region #:rt-with-remaining-timeout #:rt-with-signal-handler
   #:rt-with-span #:rt-with-try-mutex #:rt-with-write-lock #:rt-work-deque #:rt-work-deque-count
   #:rt-work-deque-p #:rt-work-deque-pop-front #:rt-work-deque-push-front #:rt-work-deque-steal-back #:rt-work-stealing-init
   #:rt-work-stealing-maybe-grow #:rt-work-stealing-run #:rt-work-stealing-scheduler #:rt-work-stealing-scheduler-p #:rt-work-stealing-submit
   #:rt-worker #:rt-worker-p #:rt-worker-run-once #:rt-write #:rt-write-byte
   #:rt-write-char #:rt-write-line #:rt-write-sequence #:rt-write-string #:rt-write-to-string
   #:rt-write-to-string-with-controls #:rt-write-tvar #:rt-yield #:rt-young-addr-p #:rt-zerop
   #:rtwhe-key #:rtwhe-key-ephemeron #:rtwhe-value #:rtwhe-value-ephemeron #:satb-drain-queue
   #:satb-write-barrier #:serialize #:set-cpu-affinity-mask #:set-default-logger #:set-pointer-color
   #:strip-pointer-color #:try-enable-huge-pages #:val->cl-value #:val-char-p #:val-compressed-pointer-p
   #:val-cons-p #:val-double-p #:val-fixnum-p #:val-function-p #:val-nil-p
   #:val-object-p #:val-pointer-p #:val-sso-string-p #:val-string-p #:val-symbol-p
   #:val-t-p #:val-unbound-p #:vm-frame #:vm-frame-closure #:vm-frame-p
   #:vm-frame-pc #:vm-frame-registers #:vm-frame-return-frame #:vm-frame-sp #:with-arena
   #:with-arena-region #:with-captured-log-context #:with-default-logger #:with-log-context #:with-log-span
   #:with-mmap #:with-pinned-objects #:without-gcing
  ))

(in-package :cl-cc/runtime)

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; These specials are defined later in the ASDF source order, but multiple
  ;; earlier runtime files refer to them during compilation.
  (declaim (special *gc-major-threshold*
                    *gc-max-pause-ms*
                    *gc-worker-count*
                    *rt-current-context*
                    *rt-current-gc-heap*
                    *rt-weak-hash-table-registry*)))

