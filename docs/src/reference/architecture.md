# Architecture

This page describes how `src/` is divided and why. It is for readers changing
the library, not using it.

## Feature packages and the facade

The implementation is divided into feature packages under `src/<feature>/`,
with each package declared in that directory's `package.lisp`. The
`cl-cc/runtime` package in `src/package.lisp` remains the compiler-facing
facade: generated calls keep their existing package name while implementation
code can depend on narrower feature interfaces.

`cl-cc-runtime.asd` loads feature package definitions before their
implementations and records the test modules under `t/<feature>/`.
`nix/feature-dependencies.sexp` records the allowed direction of feature
dependencies; feature-lint checks those declarations against package imports.
Memory, OS, and profiling also have `/infra` packages for implementation
details that should not become domain interfaces.

## Layers

The following groups locate related implementation files. The ASDF component
list, not this table, determines their load order.

| Feature | Directory | Responsibility |
|---|---|---|
| `memory` | `src/memory/` | Heap, garbage collection, allocation, and memory mapping |
| `values` | `src/values/` | Runtime value representation and codecs |
| `images` | `src/images/` | Runtime image creation and restoration |
| `concurrency` | `src/concurrency/` | Scheduling, synchronization, tasks, and memory reclamation |
| `clos` | `src/clos/` | Runtime classes, instances, and generic dispatch |
| `conditions` | `src/conditions/` | Runtime condition types and signaling |
| `dynamic-binding` | `src/dynamic-binding/` | Runtime dynamic-variable binding |
| `execution` | `src/execution/` | Runtime code cache and execution support |
| `os` | `src/os/` | Operating-system, network, and foreign-function interface (FFI) operations |
| `profiling` | `src/profiling/` | Performance counters and continuous profiling |
| `observability` | `src/observability/` | Logging, metrics, and tracing adapters |
| `serialization` | `src/serialization/` | Runtime object serialization and deserialization |
| `cryptography` | `src/cryptography/` | Digest, HMAC, and Base64 interfaces |
| `compression` | `src/compression/` | zlib and gzip interfaces |
| `resilience` | `src/resilience/` | Rate limiting |

## Why the heap is split across so many files

The `heap-` and `gc-` files are split by collection phase and allocation policy:

- `heap-data` holds the struct and the tunables; almost everything includes it.
- `heap-core`, `heap-layout`, and `heap-access` implement allocation, object
  layout, and word access. `heap-forwarding`, `heap-numa`, and `heap-stats`
  handle pointer forwarding, NUMA placement, and occupancy queries.
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
`cl-process-kit`, `cl-json-kit`, `cl-host-kit`, `cl-observability-kit`,
`cl-deflate-kit`, `cl-crypto-kit`, and `cl-resilience-kit`. Their revisions
are pinned in `flake.lock`.

The runtime keeps adapters for its public tracing, metrics, compression,
cryptography, and rate-limiting entry points. The corresponding kits provide
those primitives where available; Base64 remains local because the pinned
kits do not provide that API. Logging already uses `cl-log-kit`. Runtime-specific
formatting, string conversion, profile sampling, and hardware performance
counters stay in this repository.

`cl-host-kit` supplies process execution for the CPU feature probe in
`xom.lisp`, environment-name filtering in `os.lisp`, and string splitting
in `continuous-profile.lisp`. POSIX environment-variable name validation
for `rt-getenv`, `rt-setenv`, and `rt-unsetenv` remains local to `os.lisp`.
That validation is separate from the uses of `cl-host-kit` above.

## Threading model

The green-thread scheduler is single-native-threaded: `rt-spawn` queues a thunk
and `rt-scheduler-run` drains the queue on the calling thread. The lock-free
structures, work-stealing scheduler, and four memory-reclamation implementations
assume real parallelism: read-copy-update (RCU), epoch-based reclamation (EBR),
quiescent-state-based reclamation (QSBR), and hazard pointers.

### Queues and continuations

`rt-scheduler-run` drains green-thread queues in `*rt-global-scheduler*`.
`rt-run-fibers` drains the separate `*rt-fiber-ready*` queue. Neither runner
drains the other queue. Their `:once` option processes at most one ready item
and returns `nil` if none is ready.

`rt-yield` and `rt-sleep-task` return to the current Lisp code; neither captures
or suspends its call stack. If the thunk returns after either call, the scheduler
can queue that same thunk for another run, which starts it from its first form.
Fiber yield/block calls also return normally. To resume a fiber from a saved
point, install an explicit continuation with `rt-fiber-set-continuation` or
`rt-fiber-block`, then return from the current call.

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
(GC, runtime primitives) split further. Tests use
[cl-weave](https://github.com/nerima-lisp/cl-weave)'s forms directly:
`describe`, `it`, `it-sequential`, `it-sequential-each`, `it-property`, and
`expect`. Use these forms when adding tests.

Most subsystem tests run with `it-sequential` rather than plain `it`: many
share mutable global state (heaps, registries, scheduler queues). Preserve
sequential execution unless independence has been verified.

`t/mutation-test.lisp` reads `rt-return-address-poisoned-p` from `src/` and
uses `cl-weave:run-mutations` to rerun the same test cases against generated
mutations of that function body. The test requires every generated mutation to
be detected (a mutation score of 1.0); it covers only this function.

Test files are named `<source>-test.lisp` after the `src/` file they cover, as
CODING_STANDARD.md requires. Where one source needs several angles the name
carries the angle too: `frame-test.lisp` and `frame-boundary-test.lisp` both
cover `src/frame.lisp`, and `gc-major-sweep-test.lisp` and
`gc-major-sweep-incremental-test.lisp` both cover `src/gc-major-sweep.lisp`.
`gc-requirements-test.lisp` checks collector behavior across multiple source
files rather than a single implementation file.
