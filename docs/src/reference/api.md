# API Reference

The entry points below belong to `cl-cc/runtime`.

!!! note "Coverage"

    This page documents subsystem entry points, plus the accessors and
    constants needed to use them. Struct accessors, internal-facing hooks and
    the per-feature tuning variables are not listed individually; the complete
    export list is the `:export` clause of `src/package.lisp`, which is
    sectioned with the same headings used here.

## Heap

### `make-rt-heap`

`(make-rt-heap &key young-size old-size)`. Allocates a fresh managed heap.
Sizes are in words. `young-size` is split evenly into two semi-spaces. With
neither argument supplied the sizes are auto-configured from
`*gc-young-size-words*` and `*gc-old-size-words*`.

### `rt-heap-ref`

`(rt-heap-ref heap index)`. Reads a word at an absolute heap word index, not
a byte address.

### `rt-heap-set`

`(rt-heap-set heap index value)`. Stores a word without GC write-barrier
bookkeeping. Use `rt-gc-write-barrier` for managed object reference updates:
it handles both old-to-young cards and pre-write SATB snapshots. Do not store
the new value first; the barrier must read the old slot value itself.

### `rt-heap-object-header`

`(rt-heap-object-header heap addr)`. Reads the header at the object's word address.

### `rt-heap-set-header`

`(rt-heap-set-header heap addr new-header)`. Writes the header at the object's
word address. The caller must initialize it immediately after `rt-gc-alloc`,
which leaves the header unwritten.

### `make-rt-header`

`(make-rt-header size type-tag &key (gc-bits 0) (shape-id 0))`. Packs size, type
tag, GC bits and shape id into the one-word compressed header format.

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

`(rt-gc-alloc heap type-tag size-words)`. Returns a word address. Allocation
tries a configured slab class, then dispatches to large-object space, explicit
old-generation allocation, or young-space bump allocation. The young path
attempts minor collection on exhaustion unless GC is inhibited, then signals
an error if space is still insufficient. The caller must write the header.

### `rt-gc-add-root`

`(rt-gc-add-root heap root-cell)`. Registers a cons cell as a root. The
collector treats the cell's `cdr` as the reference and rewrites it in place
when the object moves.

### `rt-gc-remove-root`

Removes a previously registered root cell. A root that is never removed keeps
its object alive for the lifetime of the heap.

### `rt-gc-write-barrier`

`(rt-gc-write-barrier heap obj-addr slot-offset new-val)`. Performs the actual
store at `obj-addr + slot-offset`, in words. It records old-to-young cards and,
during major marking of a marked object, queues the overwritten heap pointer
for SATB processing before storing. Barrier elision paths still perform the
store. This is not a notification to call after `rt-heap-set`.

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

`(rt-gc-configure-concurrent-mode &key enabled-p write-barrier stw-phases
mutator-assist-p)`. Updates non-`nil` settings and returns a settings plist.
Passing `nil` leaves a setting unchanged; it cannot disable a true switch or
clear the phase list. To disable, set `*concurrent-gc-enabled*` or
`*rt-concurrent-gc-mutator-assist-p*` directly to `nil`.

Defaults are disabled concurrent mode, `:satb`,
`(:initial-mark :final-remark)`, and enabled mutator assistance. `write-barrier`
and `stw-phases` are reported configuration metadata; they do not select an
alternate barrier algorithm or change the collector's phase execution.

### `rt-gc-concurrent-assist`

`(rt-gc-concurrent-assist heap &key (budget 16))`. Drains SATB entries to the
grey queue, processes up to `budget` grey objects, and returns the processed
count. Returns zero unless concurrent mode, assistance, and the heap's
`:major-gc-concurrent` state are all active.

### `rt-gc-concurrent-sweep`

`(rt-gc-concurrent-sweep heap)`. Starts a host sweep worker and joins it before
returning. Falls back to a synchronous sweep if a worker cannot be started.
The caller does not regain control while the worker is running.

### `*concurrent-gc-enabled*`

Defaults to `nil`. When true, major collection enters the concurrent-marking
state; the major-collection call still completes its phases before returning.

### `*compacting-gc-enabled*`

Permits old-space compaction after major collection when the fragmentation
heuristic or configured cycle interval requests it, not after every collection.

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

`(encode-char ch)`. Converts a host Common Lisp character to a tagged 64-bit word.

### `decode-char`

`(decode-char value)`. Converts a tagged character word to a host Lisp character.

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

Takes a frame from the pool if one is available; otherwise allocates a new frame.

### `frame-pool-release`

Returns a frame to the pool.

### `initialize-frame-pool`

Fills `*frame-pool*` with `+frame-pool-size+` frames.

### `frame-reg-get`

`(frame-reg-get frame idx)`. Reads a 64-bit register; valid indices are 0 through
`+frame-register-count+ - 1` (255).

### `frame-reg-set`

`(frame-reg-set frame idx val)`. Stores a 64-bit value at the same register
indices and returns `val`.

### `+frame-register-count+`

Number of registers in a frame. The `+frame-arg-start+`,
`+frame-caller-save-start+`, `+frame-callee-save-start+`, `+frame-spill-start+`
and `+frame-return-reg+` constants divide that register file into the regions
the calling convention assigns.

### `rt-alloc-call-frame`

Allocates a call frame on the managed heap rather than from the pool, for
frames the collector has to see. `rt-free-call-frame` releases one.

## Runtime primitives

These Common Lisp-facing `rt-*` wrappers use host Lisp objects, not uniformly
the tagged 64-bit words accepted by the value codec. For example, `rt-cons`
constructs a host cons and `rt-car` reads one. Predicate wrappers such as
`rt-consp` and `rt-typep` return numeric 1 or 0, not Lisp `t` or `nil`.
Do not assume the codec's calling convention applies to these wrappers.

### `rt-cons`

Allocates a cons. `rt-car`, `rt-cdr`, `rt-rplaca` and `rt-rplacd` are the
accessors, and the rest of the list operators (`rt-append`, `rt-reverse`,
`rt-member`, `rt-nth`, `rt-assoc`, ...) follow the CL names.

### `rt-make-array`

Allocates an array. `rt-aref`, `rt-aset`, `rt-array-length`, `rt-array-rank`
and `rt-array-dimensions` are the accessors.

### `rt-typep`

Tests a host object against a type designator, returning 1 or 0. `rt-type-of`
returns the host Lisp type. The `rt-consp`, `rt-symbolp`, `rt-stringp`, and
`rt-numberp` predicates also return 1 or 0.

### `rt-make-hash-table`

Allocates a hash table; `make-hash-table` is shadowed in this package for that
reason. `rt-gethash`, `rt-sethash`, `rt-remhash`, `rt-maphash` and
`rt-hash-count` are the operations, and `rt-hash-table-weakness` reports
whether a table holds its keys or values weakly.

### `rt-boundp`

`(rt-boundp sym)` returns 1 or 0 for presence in the runtime global-variable
registry. `rt-fboundp` tests the function registry with the same numeric
result convention. `rt-makunbound` removes a variable binding and returns
the symbol; it is a mutation, not a predicate.

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
each iteration rather than the original `timeout` re-armed every time.
`rt-semaphore-wait`, `rt-barrier-wait`, `rt-rwlock-read-lock`/`-write-lock`,
and `rt-channel-send`/`-recv` use this helper. `rt-future-await` computes its
own remaining duration; `rt-mutex-lock` passes its timeout to the host lock.

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

Creates a scheduler without installing it globally. Submit to it with
`(rt-async-submit thunk :scheduler scheduler)`. To run it, dynamically bind
`*rt-global-scheduler*` to that scheduler around `(rt-scheduler-run)`.
Submission's binding ends when it returns; `rt-await*` polls whichever
scheduler is bound when await runs.

### `rt-spawn`

`(rt-spawn thunk &key priority)`. Queues a thunk as a green thread on the
global scheduler and returns the thread. `priority` is `:high`, `:normal` or
`:low`, and the scheduler drains the higher queues first.

### `rt-scheduler-run`

`(rt-scheduler-run &key once)`. Runs ready tasks in `*rt-global-scheduler*`
and waits for queued sleepers; without `:once`, stops when both queues are
empty. With `:once t`, wakes due sleepers
and runs at most one ready task, returning that thread or `nil` if none is
ready. It does not wait for a future sleeper in once mode.

### `rt-yield`

Requeues the current green thread and returns normally. It neither captures
a continuation nor exits the thunk. The scheduler marks a normally returning
thunk done; a requeued invocation starts the original thunk again.

### `rt-sleep-task`

`(rt-sleep-task seconds)`. Marks the current green thread sleeping and queues
it with an internal-clock wake time. Returns normally without suspending the
call stack. Subsequent code in the thunk still runs; a later queued invocation
starts the original thunk again.

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

`(rt-channel-send channel value &key timeout)`. A buffered send waits for room;
capacity zero waits for a receiver's handoff. Successful send returns
`(values value t)`. A condition-wait timeout returns `(values nil nil)`;
mutex-acquisition timeout returns a single `nil`. Timeout durations are seconds.
A send that begins on a closed channel signals an error.

### `rt-channel-recv`

`(rt-channel-recv channel &key timeout)`. Successful receive returns
`(values value t)`, distinguishing a received `nil` from failure. Wait timeout
or an empty closed channel returns `(values nil nil)`; mutex-acquisition
timeout returns a single `nil`. Buffered values remain receivable after close.

### `rt-channel-close`

`(rt-channel-close channel)`. Marks the channel closed, notifies all send and
receive waiters, and returns `t`. A buffered sender already waiting for space
does not recheck closure: it can still enqueue when room becomes available,
or continue waiting while full. Close does not guarantee aborting that sender.

### `rt-make-actor`

`(rt-make-actor behavior &key name supervisor mailbox-limit)`. Creates an
actor with a mailbox. Set `:mailbox-limit` here to bound the number of
queued messages; the default `nil` keeps the mailbox unbounded.
`rt-actor-send` posts a message and `rt-actor-receive` takes the next one;
both take `:timeout`. A send to a full bounded mailbox waits for room.

### `rt-make-future`

Creates an unresolved future. `rt-future-resolve` fulfils it,
`rt-future-await` blocks on a host condition variable (`:timeout` in seconds;
timeout returns no values), and `rt-future-done-p` tests resolution.
The initial mutex acquisition and the reacquisition after a wait timeout are
unbounded, so `:timeout` is not a hard end-to-end deadline.
`rt-future-then` queues a green-thread thunk that awaits the dependency before
calling the callback. Resolve the dependency before that thunk runs, or use
another native thread to resolve it. A resolver queued behind the callback
on the same native thread cannot run while the callback waits.

## Software transactional memory

### `rt-make-tvar`

Creates a transactional variable holding an initial value.

### `rt-read-tvar`

Reads the current transaction's staged write, or records a versioned read.
Use inside `rt-atomically`: outside it, the read is cached in a fallback log
without transaction validation.

### `rt-write-tvar`

Stages a write for commit by `rt-atomically`. A call outside a transaction
only updates a fallback log; it does not commit the TVar value.

### `rt-atomically`

Runs a body as a transaction, retrying on conflict.

```lisp
(let ((v (rt-make-tvar 0)))
  (rt-atomically
    (rt-write-tvar v (+ 1 (rt-read-tvar v)))
    (rt-read-tvar v)))
;; => 1
```

### `rt-retry`

Aborts the current transaction and retries it when a read variable changes.

## Fibers and effects

### `rt-make-fiber`

Creates a fiber. `rt-fiber-spawn` creates and schedules one in a single step.

### `rt-fiber-resume`

Runs the installed continuation, or the original thunk if none is installed.
`rt-fiber-yield` requeues the running fiber; `rt-fiber-block` installs a
continuation and requeues it. Both return normally, so the caller must return
from its current step to stop executing it. Without an explicit continuation,
the next run starts the original thunk again.

`rt-fiber-await` on a pending future yields and calls `rt-await*`, which polls
the global green scheduler, not the fiber queue. It does not execute a resolver
queued only as another fiber, nor preempt blocking green-thread work.

### `rt-run-fibers`

Drains the separate fiber-ready queue. `:once t` runs at most one queued fiber
and returns it, or `nil` for an empty queue. An empty queue does not establish
that every fiber is done; a suspended fiber may have no queued entry.

### `rt-fiber-local`

`(rt-fiber-local key &optional default)` reads the current fiber's map, returning
`default` for a missing key or outside a fiber. `(setf (rt-fiber-local key) value)`
writes that map and signals an error outside a fiber.

### `rt-with-handler`

`(rt-with-handler (name handler-fn) ...)` installs a named effect handler for
the body. `(rt-handle handler-fn computation-fn)` runs a computation with a
catch-all handler. `rt-perform` dispatches synchronously; `rt-resume` invokes
the active restart and returns a value to that perform call. It does not
retain a continuation after the call returns. `rt-effect-state`,
`rt-effect-error`, `rt-effect-read` and `rt-effect-write` are the built-in effects.

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

Creates a ring buffer for exactly one producer and one consumer.
`rt-spsc-try-push` and
`rt-spsc-try-pop` are the non-blocking operations, `rt-spsc-push` and
`rt-spsc-pop` the blocking ones.

## Safe memory reclamation

These are explicit protocols, not automatically selected GC backends. Callers
must follow each scheme's participation protocol and drive retirement and
reclamation themselves.

### `rt-ebr-enter`

`(rt-ebr-enter local)` enters a critical section using the local state returned
by `rt-ebr-register-thread`. `rt-ebr-leave` leaves it;
`(rt-with-ebr-critical (local) ...)` scopes it. `(rt-ebr-retire local object)`
defers freeing. `rt-ebr-collect` attempts one epoch advance and reclaims safe
entries; one call need not free a newly retired object. Leave critical sections
and call collection again as participants advance. Unregister departing threads.

### `rt-hp-protect`

`(rt-hp-protect index object &optional thread)` publishes an object in a hazard
slot; `rt-hp-clear` drops it. Register with `rt-hp-register-thread` first:
protect silently does nothing for an unregistered thread.
`rt-hp-retire-object` adds one object to a thread's retired list;
`(rt-hp-retire retired-list free-fn threshold)` operates on a list, not a single
object. `rt-hp-reclaim` frees entries not protected by any registered hazard slot.

### `rt-rcu-read-lock`

Enters an RCU read-side critical section. `rt-with-rcu-read` scopes one to a
body; read-lock registers the current reader and the final unlock removes it.
`rt-rcu-synchronize` waits for the reader registry to become empty, including
readers arriving during the wait, with an optional timeout in seconds.
A condition-wait timeout returns `nil`, but a mutex-acquisition timeout skips
the wait and still returns `t`. A timed call's `t` therefore does not guarantee
an empty reader registry.
`rt-rcu-assign-pointer` and `rt-rcu-dereference` write/read a host symbol's
`symbol-value`; they do not implement memory-ordering fences.

### `rt-qsbr-quiescent`

Reports quiescence for a thread registered with `rt-qsbr-register-thread`.
`rt-qsbr-synchronize` resets the registered participants' flags and waits for
each to report quiescence after that reset, without a timeout. A registered
caller cannot both wait and report quiescence on the same blocked thread.
`rt-qsbr-retire` adds an object to the retired batch: the next synchronization
moves it to pending, and a subsequent synchronization frees it. One round does
not free the newly retired batch.

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

The three `!` operations mutate metric objects, not registry membership.

### `rt-register-metric`

Adds a metric to the default registry, replacing an existing entry with the
same name. This registry mutation has no trailing `!` in its name.

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

`(rt-with-context (&key deadline) ...)` binds a context inherited by spawned
green threads. `deadline` is an absolute `get-internal-real-time` value, in
`internal-time-units-per-second` units, not Unix time or a duration in seconds.
For a delay of `seconds`, use `(+ (get-internal-real-time)
(* seconds internal-time-units-per-second))`.

### `rt-context-cancel`

Sets the context's cancellation flag. `rt-context-cancelled-p` also checks
ancestor cancellation and deadlines, treating a deadline as expired when the
internal clock is strictly greater than it. These checks do not interrupt work;
the caller must poll them and stop its own computation.

### `rt-context-get-deadline`

Returns the current context's own deadline, or `nil`; it does not compute the
earliest ancestor deadline. Ancestor expiry is checked by `rt-context-cancelled-p`.

### `rt-context-value`

Reads a value from the context map. `rt-with-context-value` binds one.

### `rt-context-spawn`

Spawns a green thread with a copy of the runtime context and the calling
thread's structured logging context/span id, captured with `capture-log-context`
and restored with `with-captured-log-context` around the queued thunk.

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
host socket send/receive are blocking with no timeout parameter.
`rt-set-nonblocking` records a flag without configuring the host socket.
`rt-select` reports nonempty runtime read buffers, registered writable
descriptors, and unknown error descriptors; it does not poll host readiness.
`rt-epoll-wait` returns all registered keys without honoring its timeout or
testing readiness. These APIs do not supply a host readiness-driven event loop.

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
