# Architecture

This page describes how `src/` is divided and why. It is for readers changing
the library, not using it.

## One package, many files

There is exactly one package, `cl-cc/runtime`, defined in `src/package.lisp`,
and `src/` is flat: 93 files, no subdirectories.

One package for 93 files is unusual, and it is deliberate. The consumer of this
library is a code generator, and a code generator emits calls by name. Splitting
the runtime into `cl-cc/runtime.gc`, `cl-cc/runtime.value` and so on would push
that split into the emitted code, so every time a file moved between packages
the compiler back end would have to change too. One package makes the file
layout an internal detail.

The cost is a 725-line `src/package.lisp` exporting 1434 symbols, and an ASDF
`:serial t` that fixes the load order for all 93 files. Both are accepted.

## Layers

Files fall into five layers. Later layers depend on earlier ones; nothing
depends backwards.

| Layer | Files | Contents |
|---|---|---|
| Representation | `value*`, `frame*`, `runtime-region` | NaN-boxed values, register frames, arena regions |
| Memory | `heap-*`, `gc-*` | Heap layout, allocation, the collector |
| Primitives | `runtime*` | The `rt-*` operators the compiler emits calls to |
| Concurrency | `sync`, `scheduler`, `channel`, `actor`, `stm`, `fiber`, `async*`, `effects`, `lockfree`, `ebr`, `hazard`, `rcu`, `qsbr`, `spsc` | Everything that runs more than one thing at a time |
| Platform and observability | `os`, `signals`, `net`, `mmap`, `ffi`, `io-uring`, `perf`, `otel`, `metrics`, `continuous-profile`, `log`, `topology` | The host boundary and instrumentation |

`image*`, `cluster`, `consensus`, `crdt`, `mvcc`, `crypto`, `compress`,
`serialize` and `gpu` sit on top of all five.

## Why the heap is split across so many files

`heap-` and `gc-` account for 25 of the 93 files. The split is by *phase*, not
by data structure, because that is where the seams are:

- `heap-data` holds the struct and the tunables; almost everything includes it.
- `heap-core`, `heap-layout`, `heap-access` are allocation and word access.
- `heap-free-list`, `heap-resize`, `heap-los`, `heap-hugepages` are the
  allocator's policies for old space, growth, large objects and page size.
- `gc-minor`, `gc-major-mark`, `gc-major-sweep` are the three collection
  phases, each of which can be read without the others.
- `gc-roots-objects`, `gc-write-barrier`, `gc-safepoints`, `gc-tlab` are the
  mutator-side hooks, which is what a compiler back end has to emit calls to.
- `gc-workers`, `gc-policy` and `gc-sweep-telemetry` are the scheduling and
  back-pressure decisions.

Keeping the phases apart is what makes them individually testable: `t/` has a
file per phase, and a change to the sweeper cannot silently be covered by a
marking test.

## The dependency direction at the org level

cl-cc-runtime is an L3 (domain) system at depth 3 -- the deepest system in the
nerima-lisp org. Its dependencies are `cl-log-kit`, `cl-process-kit` and
`cl-json-kit`; the longest path is `cl-log-kit` to `cl-boundary-kit` to
`cl-process-kit` to here.

Nothing in the org depends on cl-cc-runtime except `cl-cc` itself, so the
depth is a cost this repository pays alone. The alternative -- reimplementing
structured logging for the OpenTelemetry exporter, process execution for the
FFI toolchain probes, and JSON for the pprof and OTLP output -- would be three
more subsystems in a library that already has 93 files.

The depth ceiling for the org is 4. Adding a fourth dependency here would come
close enough to it to be worth discussing first.

## Threading model

The green-thread scheduler is single-native-threaded: `rt-spawn` queues a thunk
and `rt-scheduler-run` drains the queue on the calling thread. The lock-free
structures, the four reclamation schemes and the work-stealing scheduler are
the parts that assume real parallelism.

That split is why the test suite is slower than a pure library's: the
concurrency tests start real `sb-thread` threads to exercise the memory
ordering, so `checks.default` in the flake carries a 600-second timeout rather
than the org's usual 120.

## Testing

`t/` mirrors `src/` roughly one file per subsystem, with the largest subsystems
(GC, runtime primitives) split further. Tests run under
[cl-weave](https://github.com/nerima-lisp/cl-weave) through `t/package.lisp`,
which re-expresses the monorepo's `deftest` and `assert-*` forms on top of
cl-weave's `it-sequential` and `expect`. That shim exists so that suites
carried over from the cl-cc monorepo needed only an `in-package` change; new
tests can use either vocabulary.

Test files are currently named `<subject>-tests.lisp` rather than the org's
`<source>-test.lisp`. Renaming them is deferred: it touches all 66 files and
is worth doing as its own change.
