# API Reference

Everything below is exported from the single package `cl-cc/runtime`. Names are
grouped by subsystem, in roughly the order a reader meets them: heap and
collector first, then the value codec and frames, then the concurrency
primitives, then the observability and platform layers.

!!! note "Coverage"

    `cl-cc/runtime` exports roughly 1480 symbols. This page documents the entry points
    of each subsystem -- the names you call to get in, plus the accessors and
    constants needed to use them. Struct accessors, internal-facing hooks and
    the per-feature tuning variables are not listed individually; the complete
    export list is the `:export` clause of `src/package.lisp`, which is
    sectioned with the same headings used here.

    Filling in the remaining symbols is tracked as follow-up work. Anything
    documented on this page is API; anything not on this page may still be
    exported but has not been reviewed for stability.

## Heap

### `make-rt-heap`

`(make-rt-heap &key young-size old-size)`. Allocates a fresh managed heap.
Sizes are in words. `young-size` is split evenly into two semi-spaces. With
neither argument supplied the sizes are auto-configured from
`*gc-young-size-words*` and `*gc-old-size-words*`.

### `rt-heap-ref`

Reads one word at an address.

### `rt-heap-set`

Writes one word at an address. Use `rt-gc-write-barrier` instead when the word
being written lives in old space and holds a young-space reference.

### `rt-heap-object-header`

Returns the header word of the object at an address.

### `rt-heap-set-header`

Writes an object's header word. Called by the allocating code immediately after
`rt-gc-alloc`, which leaves the header unwritten on purpose.

### `make-rt-header`

`(make-rt-header size type-tag &key gc-bits)`. Packs size, type tag and GC bits
into the one-word compressed header format.

### `rt-header-size`

Extracts the object size in words from a header.

### `rt-header-type-tag`

Extracts the type tag from a header.

### `rt-header-age`

Extracts the survival count used by the promotion policy.

### `rt-young-addr-p`

True when an address falls inside the young generation.

### `rt-old-addr-p`

True when an address falls inside old space.

### `*gc-young-size-words*`

Default young generation size, in words, used when `make-rt-heap` is called
without explicit sizes.

### `*gc-old-size-words*`

Default old generation size, in words.

### `*gc-tenuring-threshold*`

Number of minor collections an object must survive before it is promoted.

### `+gc-card-size-words+`

Card size, in words, for the card table that records old-to-young writes.

## Garbage collector

### `rt-gc-alloc`

`(rt-gc-alloc heap type-tag size-words)`. Bump-allocates in young from-space
and returns the word address. Triggers a minor collection when from-space is
exhausted, and signals an error if the heap is still full afterwards. Does not
write the object header.

### `rt-gc-add-root`

`(rt-gc-add-root heap root-cell)`. Registers a cons cell as a root. The
collector treats the cell's `cdr` as the reference and rewrites it in place
when the object moves.

### `rt-gc-remove-root`

Removes a previously registered root cell. A root that is never removed keeps
its object alive for the lifetime of the heap.

### `rt-gc-write-barrier`

Records a write of a young-space reference into an old-space object, so the
next minor collection scans that card.

### `rt-gc-minor-collect`

Runs a minor collection: copies live young objects into to-space, promotes
objects past the tenuring threshold, and updates every registered root.

### `rt-gc-major-collect`

Runs a major (whole-heap) collection, including old space.

### `rt-gc-stats`

Returns a plist of counters for a heap: `:minor-gc-count`, `:major-gc-count`,
`:words-collected`, `:words-promoted`, `:young-used`, `:young-total`,
`:old-used`, `:old-total`, `:heap-occupancy-pct` and `:free-list-count`.

### `rt-gc-configure-concurrent-mode`

Selects the concurrent-marking configuration: which phases stop the world, the
write-barrier mode, and whether mutators assist.

### `rt-gc-concurrent-assist`

Performs a slice of concurrent marking work on the calling thread.

### `rt-gc-concurrent-sweep`

Sweeps old space concurrently with the mutator.

### `*concurrent-gc-enabled*`

Master switch for concurrent collection.

### `*compacting-gc-enabled*`

Enables compaction of old space after a major collection.

## Value representation

### `encode-fixnum`

Encodes an integer into the NaN-boxed representation.

### `decode-fixnum`

Recovers the integer from a NaN-boxed fixnum.

### `encode-double`

Encodes a double-float. Doubles are stored as themselves, so this is the
identity on the bit pattern.

### `decode-double`

Recovers the double-float.

### `encode-pointer`

Encodes a heap address together with a pointer tag.

### `decode-pointer`

Recovers the heap address from a boxed pointer.

### `pointer-tag`

Returns the pointer tag of a boxed pointer.

### `encode-char`

Encodes a character.

### `decode-char`

Recovers the character.

### `encode-bool`

Encodes a generalised boolean as `+val-t+` or `+val-nil+`.

### `val-fixnum-p`

True when a value is a boxed fixnum. The `val-double-p`, `val-pointer-p`,
`val-nil-p`, `val-t-p`, `val-char-p`, `val-unbound-p`, `val-object-p`,
`val-cons-p`, `val-symbol-p`, `val-function-p` and `val-string-p` predicates
follow the same pattern.

### `+val-nil+`

The singleton value for `nil`. `+val-t+` and `+val-unbound+` are the other two
singletons.

### `+fixnum-tag+`

Tag bits marking a boxed fixnum. `+fixnum-mask+` and `+fixnum-shift+` complete
the fixnum encoding, and `+tag-mask+`, `+addr-mask+`, `+ptr-base+` and
`+ptr-mask+` do the same for pointers.

### `rt-native-integer->value`

Boxes a Lisp integer, promoting to the native bignum representation when it
does not fit in a fixnum.

### `rt-native-bignum-add`

Adds two native bignums. `rt-native-bignum-sub` and `rt-native-bignum-mul` are
the other two operations, and `rt-native-bignum-to-integer` converts back.

## Register frames

### `vm-frame`

The call-frame struct: a fixed-size register array plus the stack pointer,
program counter, closure and parent-frame slots. `vm-frame-registers`,
`vm-frame-sp`, `vm-frame-pc`, `vm-frame-closure` and `vm-frame-return-frame`
are the accessors, and `vm-frame-p` is the predicate.

### `frame-pool-acquire`

Takes a frame off the frame pool rather than allocating one. Frames are pooled
because a call-heavy program needs one per call and they all have the same
shape.

### `frame-pool-release`

Returns a frame to the pool.

### `initialize-frame-pool`

Fills `*frame-pool*` with `+frame-pool-size+` frames.

### `frame-reg-get`

Reads a register from a frame.

### `frame-reg-set`

Writes a register in a frame.

### `+frame-register-count+`

Number of registers in a frame. The `+frame-arg-start+`,
`+frame-caller-save-start+`, `+frame-callee-save-start+`, `+frame-spill-start+`
and `+frame-return-reg+` constants divide that register file into the regions
the calling convention assigns.

### `rt-alloc-call-frame`

Allocates a call frame on the managed heap rather than from the pool, for
frames the collector has to see. `rt-free-call-frame` releases one.

## Runtime primitives

The `rt-*` functions mirror the Common Lisp operators the compiler emits calls
to. They are named after their CL counterparts, take and return runtime values
rather than Lisp objects, and are grouped in `src/package.lisp` under Cons/list,
Arrays/vectors, Arithmetic, Bitwise, Comparisons, Math, Strings, Characters,
Symbols, Hash tables, CLOS and I/O.

### `rt-cons`

Allocates a cons. `rt-car`, `rt-cdr`, `rt-rplaca` and `rt-rplacd` are the
accessors, and the rest of the list operators (`rt-append`, `rt-reverse`,
`rt-member`, `rt-nth`, `rt-assoc`, ...) follow the CL names.

### `rt-make-array`

Allocates an array. `rt-aref`, `rt-aset`, `rt-array-length`, `rt-array-rank`
and `rt-array-dimensions` are the accessors.

### `rt-typep`

Runtime type test. `rt-type-of` returns the runtime type, and the `rt-consp`,
`rt-symbolp`, `rt-stringp`, `rt-numberp` family are the individual predicates.

### `rt-make-hash-table`

Allocates a hash table; `make-hash-table` is shadowed in this package for that
reason. `rt-gethash`, `rt-sethash`, `rt-remhash`, `rt-maphash` and
`rt-hash-count` are the operations, and `rt-hash-table-weakness` reports
whether a table holds its keys or values weakly.

### `rt-boundp`

True when a symbol has a global value. `rt-fboundp` and `rt-makunbound` are the
other two.

## Conditions and restarts

The runtime implements its own condition system rather than reusing the host's,
because the source language's handler and restart semantics need not match
Common Lisp's. See [Conditions](conditions.md) for the condition types this
library itself signals.

### `rt-signal`

Signals a runtime condition through the runtime handler stack.

### `rt-signal-error`

Signals a runtime error.

### `rt-cerror`

Signals a continuable error.

### `rt-establish-handler`

Pushes a handler onto `*handler-stack*` for the dynamic extent of a call.

### `rt-establish-restart`

Pushes a restart onto `*restart-stack*`.

### `rt-find-restart`

Looks a restart up by name.

### `rt-invoke-restart`

Transfers control to a restart.

### `rt-restart-case`

Runtime counterpart of `restart-case`. `rt-restart-bind` is the counterpart of
`restart-bind`.

## Synchronisation

### `rt-make-mutex`

Creates a mutex. `rt-with-mutex` is the scoped form and the preferred way to
use one: it releases the mutex on every exit path, including a non-local
one, and -- with `:timeout` -- runs its body at all only if the lock was
actually acquired in time. `rt-mutex-lock`, `rt-mutex-try-lock` and
`rt-mutex-unlock` are the manual operations `rt-with-mutex` is built on, and
`rt-make-recursive-mutex` plus `rt-with-recursive-mutex` give the reentrant
variant.

### `rt-with-remaining-timeout`

`(rt-with-remaining-timeout (remaining-fn timeout) &body body)`. Binds
`remaining-fn` to a function returning the seconds left before `timeout`
elapses, recomputed on every call (or `nil`, unbounded, when `timeout` is
`nil`). For writing a retry loop whose wait call needs a shrinking duration
each iteration rather than the original `timeout` re-armed every time --
the shape `rt-mutex-lock`, `rt-semaphore-wait`, `rt-barrier-wait`,
`rt-rwlock-read-lock`/`-write-lock`, `rt-channel-send`/`-recv` and
`rt-future-await` all use internally.

### `rt-make-rwlock`

Creates a reader-writer lock. `rt-with-read-lock` and `rt-with-write-lock` are
the scoped forms; `rt-rwlock-try-read-lock` and `rt-rwlock-try-write-lock` are
the non-blocking ones.

### `rt-make-semaphore`

Creates a counting semaphore. `rt-semaphore-wait`, `rt-semaphore-try-wait` and
`rt-semaphore-signal` operate on it.

### `rt-make-barrier`

Creates a barrier for a fixed number of participants. `rt-barrier-wait` blocks
until all arrive; `rt-barrier-reset` reuses it.

### `rt-make-condition-variable`

Creates a condition variable. `rt-condition-wait` blocks until notified (or
`:timeout` elapses); `rt-condition-notify` and `rt-condition-notify-all`
wake one or every waiter. `rt-condition-wait-until` wraps `rt-condition-wait`
in a loop against a predicate, to tolerate spurious wakeups.

### `rt-make-once`

Creates a once-only guard; `rt-once-call` runs its thunk at most once.

## Scheduler and green threads

### `rt-scheduler-init`

Installs a fresh global scheduler, which `rt-spawn` and `rt-scheduler-run`
then operate on implicitly. Takes no arguments.

### `rt-make-scheduler`

Creates a scheduler value without installing it globally.

### `rt-spawn`

`(rt-spawn thunk &key priority)`. Queues a thunk as a green thread on the
global scheduler and returns the thread. `priority` is `:high`, `:normal` or
`:low`, and the scheduler drains the higher queues first.

### `rt-scheduler-run`

Runs queued green threads. With `:once` it runs exactly one ready task and
returns it.

### `rt-yield`

Puts the current green thread back on the ready queue.

### `rt-sleep-task`

Suspends the current green thread until a wall-clock deadline.

### `rt-current-thread-id`

Returns the current green thread's id, or `nil` outside one.

### `rt-make-work-stealing-scheduler`

Creates a work-stealing scheduler over several workers.
`rt-work-stealing-submit` queues work and `rt-work-stealing-run` drains it.

## Channels, actors, futures

### `rt-make-channel`

`(rt-make-channel &key capacity)`. Creates a CSP channel. Capacity 0 is a
rendezvous channel.

### `rt-channel-send`

`(rt-channel-send channel value &key timeout)`. Sends, blocking when the
channel is full.

### `rt-channel-recv`

Receives from a channel.

### `rt-channel-close`

Closes a channel.

### `rt-make-actor`

Creates an actor with a mailbox. `rt-actor-send` posts a message and
`rt-actor-receive` takes the next one; both take `:timeout`. With
`:mailbox-limit`, `rt-actor-send` blocks for room rather than growing the
mailbox without bound once it holds that many messages; the default `nil`
keeps the mailbox unbounded.

### `rt-make-future`

Creates an unresolved future. `rt-future-resolve` fulfils it,
`rt-future-await` blocks for the value, `rt-future-done-p` tests it and
`rt-future-then` chains a continuation.

## Software transactional memory

### `rt-make-tvar`

Creates a transactional variable holding an initial value.

### `rt-read-tvar`

Reads a transactional variable, recording the read in the current transaction.

### `rt-write-tvar`

Writes a transactional variable.

### `rt-atomically`

Runs a body as a transaction, retrying on conflict.

```lisp
(let ((v (rt-make-tvar 0)))
  (rt-atomically (rt-write-tvar v (+ 1 (rt-read-tvar v))))
  (rt-read-tvar v))
;; => 1
```

### `rt-retry`

Aborts the current transaction and retries it when a read variable changes.

## Fibers and effects

### `rt-make-fiber`

Creates a fiber. `rt-fiber-spawn` creates and schedules one in a single step.

### `rt-fiber-resume`

Resumes a suspended fiber. `rt-fiber-yield` suspends the running one, and
`rt-fiber-block` and `rt-fiber-await` are the blocking forms.

### `rt-run-fibers`

Runs scheduled fibers to completion.

### `rt-fiber-local`

Accesses fiber-local storage.

### `rt-with-handler`

Installs handlers for algebraic effects over a body. `rt-perform` raises an
effect, `rt-handle` dispatches it, and `rt-resume` continues the computation
from the handler. `rt-effect-state`, `rt-effect-error`, `rt-effect-read` and
`rt-effect-write` are the built-in effects.

## Lock-free data structures

### `rt-make-lfstack`

Creates a lock-free stack. `rt-lfstack-push`, `rt-lfstack-pop` and
`rt-lfstack-empty-p` operate on it.

### `rt-make-lfqueue`

Creates a lock-free queue. `rt-lfqueue-push`, `rt-lfqueue-pop` and
`rt-lfqueue-empty-p` operate on it.

### `rt-make-lfhash-map`

Creates a lock-free hash map. `rt-lfhash-get`, `rt-lfhash-cas`,
`rt-lfhash-remove` and `rt-lfhash-count` operate on it.

### `rt-make-spsc-queue`

Creates a single-producer single-consumer ring buffer, the cheapest of the
queues when the access pattern allows it. `rt-spsc-try-push` and
`rt-spsc-try-pop` are the non-blocking operations, `rt-spsc-push` and
`rt-spsc-pop` the blocking ones.

## Safe memory reclamation

Four schemes are provided because they trade reader cost against reclamation
latency differently, and a compiler back end picks per workload.

### `rt-ebr-enter`

Enters an epoch-based reclamation critical section. `rt-ebr-leave` leaves it,
`rt-with-ebr-critical` scopes one to a body, `rt-ebr-retire` defers a free and
`rt-ebr-collect` reclaims what has become safe.

### `rt-hp-protect`

Publishes a hazard pointer protecting one object. `rt-hp-clear` drops it,
`rt-hp-retire` defers a free and `rt-hp-reclaim` frees what is no longer
protected. Threads must call `rt-hp-register-thread` first.

### `rt-rcu-read-lock`

Enters an RCU read-side critical section. `rt-with-rcu-read` scopes one to a
body, `rt-rcu-synchronize` waits for a grace period, and
`rt-rcu-assign-pointer` and `rt-rcu-dereference` are the ordered accessors.

### `rt-qsbr-quiescent`

Reports a quiescent state for the calling thread. `rt-qsbr-retire` defers a
free and `rt-qsbr-synchronize` waits for every registered thread to pass
through one.

## Memory allocators

### `make-arena`

Creates a bump-pointer arena. `arena-alloc` allocates from it, `arena-reset`
frees everything at once, and `with-arena` scopes one to a body. An arena is
the right allocator for a compiler pass whose whole working set dies together.

### `make-object-pool`

Creates a fixed-size object pool. `pool-acquire` and `pool-release` are the
operations.

### `rt-alloc`

Size-class allocator entry point. `rt-free` returns memory to it and
`rt-size-class-for` reports the class a size falls into.

## Observability

### `rt-make-counter`

`(rt-make-counter name &key labels)`. Creates a monotonically increasing
counter. `rt-counter-increment!` advances it.

### `rt-make-gauge`

Creates a gauge. `rt-gauge-set!` sets its value.

### `rt-make-histogram`

Creates a histogram. `rt-histogram-observe!` records a sample.

The trailing `!` marks the three mutating operations, so a call that changes
the registry is distinguishable from a call that only reads it.

### `rt-register-metric`

Adds a metric to the default registry.

### `rt-metrics-format-prometheus`

Renders the registry in the Prometheus text exposition format.

### `rt-perf-read-counter`

Reads a hardware performance counter. `rt-perf-enable-counter` turns one on and
`rt-with-perf-counters` scopes a measurement to a body. On a platform without
counters these signal `perf-counters-unsupported`. `rdtsc` and `rdtscp` read
the timestamp counter directly.

### `rt-otel-start-span`

Starts an OpenTelemetry span. `rt-otel-end-span` closes it, and the exporter
serialises spans with cl-json-kit.

### `rt-start-continuous-profile`

Starts continuous profiling at a sample rate. `rt-stop-continuous-profile`
stops it, `rt-record-profile-sample` records one sample by hand, and
`rt-export-continuous-profile`, `rt-continuous-profile-to-otel-json` and
`rt-continuous-profile-to-pprof-json` render the result.

### `rt-deadlock-detect`

Runs the wait-for-graph deadlock detector over the current lock set.

## Context propagation

### `rt-with-context`

Binds a context over a body. Contexts carry a cancellation signal, a deadline
and a value map, and are inherited by green threads created inside them.

### `rt-context-cancel`

Cancels a context. `rt-context-cancelled-p` tests it.

### `rt-context-get-deadline`

Returns the context deadline, if any.

### `rt-context-value`

Reads a value from the context map. `rt-with-context-value` binds one.

### `rt-context-spawn`

Spawns a green thread that inherits the current context, and also carries
the calling thread's cl-log-kit structured-logging context and span id into
it, via `capture-log-context`/`with-captured-log-context` -- the same
propagation cl-log-kit documents for `sb-thread:make-thread`, applied here
because `rt-spawn`'s queued thunk runs from a different point on the call
stack than the spawning call.

## Platform and OS

### `rt-getenv`

Reads an environment variable; `rt-setenv` and `rt-unsetenv` are the writers.
The rest of the OS facade -- `rt-run-program`, `rt-fork`, `rt-exec`,
`rt-waitpid`, `rt-exit`, `rt-getcwd`, `rt-chdir`, `rt-sleep`,
`rt-gettime-monotonic` -- is in the OS abstraction section of
`src/package.lisp` and sits on `sb-posix` and `sb-ext`.

### `rt-platform`

Returns the host platform. `rt-platform-darwin-p` and `rt-platform-linux-p`
are the two tests the rest of the tree branches on.

### `rt-set-signal-handler`

Installs a handler for an OS signal, named by `+rt-sigint+`, `+rt-sigterm+` and
the rest of the `+rt-sig*+` constants. `rt-with-signal-handler` scopes one to a
body and `rt-process-pending-signals` drains the queue at a safe point. See
[Conditions](conditions.md) for the condition types signals become.

### `mmap-file`

Maps a file into memory, returning an `rt-mmap-region`. `with-mmap` scopes one
to a body, `mmap-sync` flushes it, `mmap-close` unmaps it, and `mmap-array`
maps a file as a typed array.

### `rt-socket`

Creates a socket. `rt-bind`, `rt-listen`, `rt-accept` and `rt-connect` set up a
connection, `rt-socket-send` and `rt-socket-recv` move bytes, and
`rt-set-nonblocking` with `rt-select` or `rt-epoll-wait` drives an event loop.

### `rt-ffi-load-library`

Loads a shared library. `rt-define-foreign-function` declares an entry point,
`rt-foreign-funcall` calls one, and `rt-define-foreign-struct` with
`rt-ffi-struct-field-offset` describes foreign layouts.

### `rt-pin-object`

Keeps an object at a fixed address for the duration of a foreign call, so the
collector cannot move it out from under C. `rt-unpin-object` releases it,
`rt-object-pinned-p` tests it, and `with-pinned-objects` scopes a set of pins
to a body.

### `detect-cpu-cores`

Reports the CPU count. `detect-numa-topology` and `memory-tier-info` describe
the memory hierarchy, and `rt-thread-set-affinity` pins a thread -- all of it
feeding the work-stealing scheduler and NUMA-local GC.

## Images

### `rt-capture-image-state`

Captures the runtime state -- registered globals and the schema version -- into
an image value.

### `rt-save-image`

Writes an image to a file in the binary format. `rt-load-image` reads one back
and detects corruption. `rt-save-core` and `rt-load-core` do the same for a
full SBCL core.

### `rt-restore-image-state`

Restores captured state into the running runtime, running every registered
restore hook.

### `rt-image-register-global`

Registers a global to be included in captures.
`rt-image-register-restore-hook` adds a hook to run after a restore, and
`rt-hot-reload` drives the reload path that uses both.
