# Architecture

This page describes how `src/` is divided and why. It is for readers changing
the library, not using it.

## One package, many files

There is exactly one package, `cl-cc/runtime`, defined in `src/package.lisp`,
and the Lisp source files sit directly in `src/`.

The consumer of this library is a code generator, which emits calls by name. Splitting
the runtime into `cl-cc/runtime.gc`, `cl-cc/runtime.value` and so on would push
that split into the emitted code, so every time a file moved between packages
the compiler back end would have to change too. One package makes the file
layout an internal detail.

`src/package.lisp` declares the exported interface, and ASDF `:serial t`
fixes the load order. `package.lisp` and the similarly manifest-shaped
`runtime-packages.lisp` are the two files in this tree exempt from the file
length guidance in `CODING_STANDARD.md`: a package definition is a flat list, not a place
where splitting reduces complexity the way it does for logic.

## Layers

The following groups locate related implementation files. The ASDF component
list, not this table, determines their load order.

| Layer | Files | Contents |
|---|---|---|
| Representation | `value*`, `frame*`, `runtime-region` | NaN-boxed values, register frames, arena regions |
| Memory | `heap-*`, `gc-*` | Heap layout, allocation, the collector |
| Primitives | `runtime*` | The `rt-*` operators the compiler emits calls to |
| Concurrency | `sync`, `scheduler`, `channel`, `actor`, `stm`, `fiber`, `async*`, `effects`, `lockfree`, `ebr`, `hazard`, `rcu`, `qsbr`, `spsc` | Scheduling, synchronization, continuations, and memory reclamation |
| Platform and observability | `os`, `signals`, `net`, `mmap`, `ffi`, `io-uring`, `perf`, `otel`, `metrics`, `continuous-profile`, `log`, `topology` | The host boundary and instrumentation |

`image*`, `cluster`, `consensus`, `crdt`, `mvcc`, `crypto`, `compress`,
`serialize` and `gpu` implement additional services.

## Why the heap is split across so many files

The `heap-` and `gc-` files are split by collection phase and allocation policy:

- `heap-data` holds the struct and the tunables; almost everything includes it.
- `heap-core`, `heap-layout`, `heap-access` are allocation and word access;
  `heap-forwarding`, `heap-numa` and `heap-stats` are relocation/compressed
  pointers, NUMA placement, and occupancy queries, split out of `heap-access`
  because each reads independently of the word-access primitives.
- `heap-free-list`, `heap-resize`, `heap-los`, `heap-hugepages` are the
  allocator's policies for old space, growth, large objects and page size.
- `gc-minor`, `gc-major-mark`, `gc-mark-work`, `gc-major-sweep`, `gc-compact`,
  `gc-concurrent-sweep`, `gc-major-collect` are the collection phases:
  configuration and the tri-color mark work are separate from the sweep pass,
  which is itself separate from compaction, the concurrent worker, and the
  top-level orchestrator that drives all of them.
- `gc-roots-objects`, `gc-stackmaps`, `gc-binding-scan`, `gc-heap-verify`,
  `gc-alloc`, `gc-copy`, `gc-write-barrier`, `gc-safepoints`, `gc-tlab` are the
  mutator-side hooks, which is what a compiler back end has to emit calls to.
- `gc-workers`, `gc-policy`, `gc-pinning` and `gc-sweep-telemetry` are the
  scheduling, back-pressure and FFI-pinning decisions.
- `gc-references` and `gc-weak-processing` are the soft/weak/phantom
  reference and hash-consing primitives, and the GC-time passes that process
  them (ephemerons, weak hash tables).

`t/` has tests for individual phases. A sweeper change needs sweeper tests;
passing a marking test alone does not verify it.

## Dependencies

`cl-cc-runtime.asd` declares direct dependencies on `cl-log-kit`,
`cl-process-kit`, `cl-json-kit`, and `cl-host-kit`. Their revisions are pinned
in `flake.lock`.

`cl-host-kit` supplies process execution for the CPU feature probe in
`xom.lisp`, environment-name filtering in `os.lisp`, and string splitting
in `continuous-profile.lisp`. POSIX environment-variable name validation
for `rt-getenv`, `rt-setenv`, and `rt-unsetenv` remains local to `os.lisp`.
That validation is separate from the uses of `cl-host-kit` above.

## Threading model

The green-thread scheduler is single-native-threaded: `rt-spawn` queues a thunk
and `rt-scheduler-run` drains the queue on the calling thread. The lock-free
structures, the four reclamation schemes and the work-stealing scheduler are
the parts that assume real parallelism.

`checks.default` in `flake.nix` sets `timeoutSeconds = 600`.

### Queues and continuations

`rt-scheduler-run` drains green-thread queues in `*rt-global-scheduler*`.
`rt-run-fibers` drains the separate `*rt-fiber-ready*` queue. Neither runner
drains the other queue. Their `:once` option processes at most one ready item
and returns `nil` if none is ready.

`rt-yield` and `rt-sleep-task` update green-thread queues and return normally;
they do not capture or suspend the current Lisp call stack. When the thunk
returns, the scheduler marks it done. A later queued invocation starts that
same thunk again. Fiber yield/block calls also return normally. For a fiber
to resume at a different point, install an explicit continuation with
`rt-fiber-set-continuation` or `rt-fiber-block` and return from the current call.

`rt-fiber-await` yields and calls `rt-await*` on a pending future. The await
poll loop runs the global green scheduler, not the fiber queue. A future whose
resolver is only queued as another fiber therefore needs a separate driver;
await does not run that resolver itself. The poll loop cannot preempt blocking
green-thread work.

`rt-async-cps-transform` (`async.lisp`) constructs continuations using
`rt-future-then`. Each `rt-future-then` callback is a queued green-thread thunk
that first blocks in `rt-future-await`. Resolve its dependency before that
thunk runs, or provide a resolver on another native thread. A resolver queued
behind the callback on the same thread cannot run while the callback waits.

`effects.lisp` dispatches handlers synchronously inside `rt-perform`'s
`restart-case`. `rt-resume` invokes the active `rt-resume` restart, returning
a value to the perform call. This is a dynamically scoped restart, not a
stored fiber continuation that can be resumed after the call has returned.

## Testing

`t/` mirrors `src/` roughly one file per subsystem, with the largest subsystems
(GC, runtime primitives) split further. Tests run under
[cl-weave](https://github.com/nerima-lisp/cl-weave)'s native vocabulary
directly: `describe`/`it`/`it-sequential`/`it-sequential-each`/`it-property`
and `expect`. Use that vocabulary when adding tests.

Most subsystem tests run with `it-sequential` rather than plain `it`: many
share mutable global state (heaps, registries, scheduler queues). Preserve
sequential execution unless independence has been verified.

`t/mutation-test.lisp` reads `rt-return-address-poisoned-p` from `src/` and
uses `cl-weave:run-mutations` to re-run a case battery against mutations of
its body. The test requires a mutation score of 1.0; it does not establish
mutation coverage of other functions.

Test files are named `<source>-test.lisp` after the `src/` file they cover, as
CODING_STANDARD.md requires. Where one source needs several angles the name
carries the angle too: `frame-test.lisp` and `frame-boundary-test.lisp` both
cover `src/frame.lisp`, and `gc-major-sweep-test.lisp` and
`gc-major-sweep-incremental-test.lisp` both cover `src/gc-major-sweep.lisp`.
`gc-requirements-test.lisp` checks collector behavior across multiple source
files rather than a single implementation file.
