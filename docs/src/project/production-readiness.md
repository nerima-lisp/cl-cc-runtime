# Production readiness

This page describes the verification gates and known limitations. A passing
check applies to the revision and platform tested, not to later source changes
or other platforms.

## Correctness and testing

The suite uses [cl-weave](https://github.com/nerima-lisp/cl-weave), including
known-answer tests, property tests, and fuzz tests. `nix flake check` runs the
test, documentation, and formatting gates (see [Development](development.md)).
Release verification must run these gates against the candidate revision;
this page is not a record of a passing run.

`t/mutation-test.lisp` reads the current source of
`rt-return-address-poisoned-p`, checks its result against a case battery, and
requires a mutation score of 1.0 with
`cl-weave:run-mutations`/`assert-mutation-score`. This covers that function,
not the full source tree (see [Architecture](../reference/architecture.md#testing)).

`scripts/run-coverage.lisp` instruments the runtime with `sb-cover`, runs the
suite, and writes an HTML report. It is not part of the release gate, and no
numeric coverage target is enforced. This page reports no coverage percentage.

## Blocking operations

Use the documented `:timeout` parameter when a blocking operation must be
bounded; durations are in seconds. `rt-channel-send` and `rt-channel-recv`
use `rt-with-remaining-timeout` for their condition-wait loops;
`rt-future-await` computes its own remaining duration. Channel operations
acquire their mutex using the original timeout; future await acquires and
reacquires its mutex without a timeout. Neither is a hard end-to-end deadline.
`rt-await*` polls the global
green scheduler, but cannot preempt a queued thunk that blocks. A successful
timeout test for one primitive does not bound every blocking path.

`rt-with-mutex`, `rt-with-recursive-mutex`, `rt-with-read-lock`, and
`rt-with-write-lock` return `nil` without running their body when timed lock
acquisition fails. The same return value can come from a body that ran and
returned `nil`; callers needing to distinguish those outcomes must arrange
their own success value.

Set `:mailbox-limit` on `rt-make-actor` to bound its mailbox; the default is
`nil` (unbounded). `rt-actor-send` accepts `:timeout` for waiting for space and
the mailbox lock. Consumers must continue receiving messages to make room.

`rt-socket-send` and `rt-socket-recv` use blocking host socket operations and
do not accept a timeout. `rt-set-nonblocking` only records a runtime flag; it
does not configure the host socket. `rt-select` checks runtime buffers and
registry state, and `rt-epoll-wait` returns registered descriptors without
waiting for host readiness. These APIs do not provide host readiness-driven
I/O. `rt-fork-join` waits for caller-supplied
work; it does not impose a completion deadline on that work.

## Error handling

The conditions defined in `src/runtime-conditions.lisp` derive from
`rt-runtime-condition`, with `rt-runtime-error` for its error subset (see
[Conditions](../reference/conditions.md)). This hierarchy is not a universal
wrapper: runtime calls can also signal host Common Lisp errors, including
argument-validation and operating-system failures.

The runtime has a separate condition/handler/restart system (`rt-signal`,
`rt-establish-handler`, `rt-restart-case`, and related functions) for compiled
target programs. Do not confuse those target handlers with host Lisp handlers.

## Concurrency and instrumentation

Epoch-based reclamation, hazard pointers, RCU, and QSBR require participation
in their critical-section and reclamation protocols; the runtime does not
select a scheme automatically. RCU read-lock registers readers implicitly (see
[Safe memory reclamation](../reference/api.md#safe-memory-reclamation)).

Deadlock bookkeeping is disabled by default. Bind `*rt-dl-enabled*` to true to
record lock dependencies, then call `rt-deadlock-detect` to inspect them. Heap
sanitizer switches `*rt-asan-enabled*`, `*rt-msan-enabled*`, `*rt-tsan-enabled*`,
`*rt-hwasan-enabled*`, and `*rt-ubsan-enabled*` also default to `nil`. These are
software checks against managed-heap bookkeeping, not native hardware
instrumentation. `t/heap-sanitizer-test.lisp` exercises invalid accesses.

Logging uses `cl-log-kit`. `rt-context-spawn` propagates runtime context and
structured logging context across the green-thread queue boundary. The
runtime also provides OpenTelemetry and Prometheus-format export, continuous
profiling, and hardware performance counters. Host counter availability and
permissions depend on the platform; see [Conditions](../reference/conditions.md)
for the unsupported-counter condition.

## Dependency and build hygiene

The runtime depends on `cl-log-kit`, `cl-process-kit`, `cl-json-kit`, and
`cl-host-kit`. `flake.lock` records the dependency revisions. The ASDF
`:version` in `cl-cc-runtime.asd` is the version source of truth; `flake.nix`
reads it, and the release workflow checks that the tag agrees with it.

Run `nix flake check` for the compile/test, formatting, and strict documentation
gates. A local source test does not replace the packaged build or establish
that a different platform passes.

## Known limitations

- The default green-thread scheduler is cooperative and single-native-threaded.
  Real parallelism requires the work-stealing scheduler or native threads (see
  [Core Concepts](../guide/core-concepts.md#concurrency-is-cooperative-by-default)).
- Many tests share global state and require sequential execution (see
  [Architecture](../reference/architecture.md#testing)).
- Passing subsystem tests do not establish whole-program correctness for every
  compiler consumer, input, or platform.
