# Architecture

This page describes how `src/` is divided and why. It is for readers changing
the library, not using it.

## One package, many files

There is exactly one package, `cl-cc/runtime`, defined in `src/package.lisp`,
and `src/` is flat: 125 files, no subdirectories.

One package for 125 files is unusual, and it is deliberate. The consumer of this
library is a code generator, and a code generator emits calls by name. Splitting
the runtime into `cl-cc/runtime.gc`, `cl-cc/runtime.value` and so on would push
that split into the emitted code, so every time a file moved between packages
the compiler back end would have to change too. One package makes the file
layout an internal detail.

The cost is a 729-line `src/package.lisp` exporting roughly 1480 symbols, and
an ASDF `:serial t` that fixes the load order for all 125 files. Both are
accepted. `package.lisp` and the similarly manifest-shaped
`runtime-packages.lisp` are the two files in this tree exempt from the file
length guidance below -- a package definition is a flat list, not a place
where splitting reduces complexity the way it does for logic.

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

`heap-` and `gc-` account for 37 of the 125 files. The split is by *phase*, not
by data structure, because that is where the seams are:

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
more subsystems in a library that already has 125 files.

The depth ceiling for the org is 4. Adding a fourth dependency here would come
close enough to it to be worth discussing first.

### Why not cl-dataflow-kit

`cl-dataflow-kit` (computation graphs, pipelines, state machines, effect
boundaries) is an L3 sibling that looks adjacent to `reactive.lisp` and
`effects.lisp` on the surface. It is not a fit: both of those files implement
a specific low-level protocol by name -- Reactive Streams'
`on-subscribe`/`on-next`/`on-error`/`on-complete` and an algebraic-effect
handler stack -- that the cl-cc compiler emits code against. `cl-dataflow-kit`'s
`define-pipeline`/`:node`/`:edge` model operates one layer up, at named-graph
orchestration. Adopting it here would mean wrapping its graph API to fake the
protocol shape downstream code already targets, which is exactly the kind of
adapter indirection this codebase avoids. It also sits at the same layer as
this system rather than below it, which the org's dependency policy treats as
a default-reject case pending justification. Left as a dependency other
`cl-cc-*` domain systems (application-level pipelines, not runtime
primitives) may have real use for.

### Other org packages evaluated and declined

`cl-parser-kit`, `cl-cli`, `cl-tty-kit` and `cl-history-kit` solve problems
this library does not have -- text-language parsing, CLI argument dispatch,
terminal rendering, and interactive command recall are all absent from a
runtime a compiler emits calls against. `cl-date-kit`'s calendar and IANA
timezone arithmetic has no consumer here; every clock read in this tree goes
through `rt-gettime-monotonic`, not a calendar. `cl-regex-kit` has no
string-pattern call site to replace.

`cl-concurrent-kit` is the same shape mismatch as `cl-dataflow-kit` above: it is
a bordeaux-threads-style portable primitive set, one layer up from what this
library needs. `sync.lisp`'s primitives are named `rt-*` because the
compiler back end emits calls to them by that exact name, not because this
runtime lacks a mutex/condition-variable facade -- adopting `cl-concurrent-kit`
would mean either wrapping its API behind `rt-*` adapters (the pattern this
codebase avoids) or renaming the ABI surface itself, which is out of scope
for what would be an unrelated dependency swap.

`cl-host-kit` came closest: its `getenv`/`(setf getenv)` validate a POSIX
environment-variable name (rejecting `=` and NUL) before calling
`sb-posix:setenv`/`unsetenv`, a check `os.lisp`'s `rt-getenv`/`rt-setenv`
lacked. But the org's `DEPENDENCY_POLICY.md` asks that a dependency be
weighed against duplicating the code first when the API surface used is one
or two symbols and the implementation is under 50 lines and specifies
something that will not change -- POSIX's environment-variable grammar
qualifies on both counts. `rt-getenv`/`rt-setenv`/`rt-unsetenv` now carry
that same validation, ported with a sourcing comment rather than pulled in
as a new dependency.

## Threading model

The green-thread scheduler is single-native-threaded: `rt-spawn` queues a thunk
and `rt-scheduler-run` drains the queue on the calling thread. The lock-free
structures, the four reclamation schemes and the work-stealing scheduler are
the parts that assume real parallelism.

That split is why the test suite is slower than a pure library's: the
concurrency tests start real `sb-thread` threads to exercise the memory
ordering, so `checks.default` in the flake carries a 600-second timeout rather
than the org's usual 120.

### Why fiber/event-loop/effects don't use the async CPS transform

`rt-async-cps-transform` (`async.lisp`) rewrites a computation into explicit
continuations built on `rt-future-then`, which itself works by spawning a new
task on the scheduler that blocks on a real condition variable and invokes
the callback when it wakes. That is only safe when some *other* native thread
can resolve the future concurrently.

`rt-fiber-await` (`fiber.lisp`) cannot use that path: fibers run under
`rt-run-fibers`/`rt-scheduler-run`, which drain their queue cooperatively on
a single native thread. Routing a fiber's await through `rt-future-then`
would spawn a queued thunk that blocks that same thread on a condition
variable no other thread will ever signal -- a deadlock, not a simplification.
`rt-fiber-await` instead yields cooperatively in a poll loop, which is the
correct shape for a single-native-thread scheduler, not a gap to close.

`effects.lisp`'s handler dispatch is a continuation mechanism already: each
`rt-perform` call suspends via `restart-case`/`rt-resume`, and the CL
condition system supplies the one-shot resumable continuation for free.
Reimplementing that as an explicit closure chain would duplicate what
`invoke-restart` already does, with none of its dynamic-extent unwinding
guarantees.

`event-loop.lisp`'s fd/timer callbacks are persistent registrations, not a
sequential computation with a "rest of the program" to transform -- there is
no continuation for `rt-async-cps-transform` to build, only a handler to
invoke on every tick.

## Testing

`t/` mirrors `src/` roughly one file per subsystem, with the largest subsystems
(GC, runtime primitives) split further. Tests run under
[cl-weave](https://github.com/nerima-lisp/cl-weave)'s native vocabulary
directly: `describe`/`it`/`it-sequential`/`it-sequential-each`/`it-property`
and `expect`. `t/package.lisp` used to also define a `deftest`/`assert-*`
compatibility shim carried over from the cl-cc monorepo's older test style;
every call site across all of `t/` has since been converted to cl-weave
directly and the shim removed, so there is exactly one vocabulary to write
new tests in.

Most subsystem tests run with `it-sequential` rather than plain `it`: many
share mutable global state (heaps, registries, scheduler queues) accumulated
from the original monorepo suites, so ordering is currently a correctness
requirement rather than a style choice. Auditing which suites are actually
independent enough for `it`'s default (possibly concurrent) execution is
tracked as follow-up work, not assumed.

At least one subsystem per the org's mutation-testing floor is verified with
`cl-weave:run-mutations` (see `t/mutation-test.lisp`): the live case battery
for a pure function is re-run against every single-operator mutation of that
function's real body, read straight from `src/`, and the whole suite fails if
any mutation survives undetected. This catches what line/branch coverage
cannot -- that a wrong result would actually be noticed, not just that the
line ran.

Test files are named `<source>-test.lisp` after the `src/` file they cover, as
CODING_STANDARD.md requires. Where one source needs several angles the name
carries the angle too: `frame-test.lisp` and `frame-boundary-test.lisp` both
cover `src/frame.lisp`, and `gc-major-sweep-test.lisp` and
`gc-major-sweep-incremental-test.lisp` both cover `src/gc-major-sweep.lisp`.
`gc-requirements-test.lisp` is the one file named for what it verifies rather
than for a single source: it is FR evidence spanning the whole collector.
