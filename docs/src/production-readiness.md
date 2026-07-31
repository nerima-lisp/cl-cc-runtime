# Production readiness

This is a written audit against concrete criteria, not a claim that every box
is checked. Where something is genuinely incomplete, it says so; a checklist
that cannot fail is not doing its job.

## Correctness and testing

The suite is 1142 tests under [cl-weave](https://github.com/nerima-lisp/cl-weave),
run by `nix flake check` on every change (see [Development](development.md)),
re-verified against this working tree with `nix build
.#checks.<system>.default/.docs/.formatting` -- all three green.
It mixes plain `it`/`it-sequential` cases, table-driven `it-sequential-each`
known-answer batteries (SHA-256/SHA-512/HMAC/Base64 against published
vectors), `it-property` round-trip checks, and one `it-fuzz` test -- the
fuzz test found a real out-of-bounds read in `rt-base64-decode` the first
time it ran (see the Changelog's `[Unreleased] Fixed` section).

At least one function per the org's mutation-testing floor is verified with
`cl-weave:run-mutations`/`assert-mutation-score` at a score of 1.0 (see
[Architecture](architecture.md#testing)): every single-operator mutation of
that function's real body is caught by its existing case battery, not just
executed by it. This is deeper evidence than line coverage, which this
project does not currently report as a percentage -- `sb-cover` requires
recompiling every source file with instrumentation, and that recompilation
starves on the machine this was developed on. This was re-checked rather
than taken on faith, twice. First, a plain (non-instrumented) `nix develop -c
sbcl --script run-tests.lisp` run also stalled past any reasonable
interactive budget while several sibling nerima-lisp repositories' own test
suites were compiling concurrently, and killing the local `result` symlink
first (so ASDF's own `(:tree ...)` source-registry entry in `run-tests.lisp`
could not wander into the Nix store through it) made no difference -- ruling
out a source-registry bug as the cause. Second, `scripts/run-coverage.lisp`
was launched as a detached process (`nohup ... &`, immune to any single
command's own timeout) and observed directly with `ps`: at 41 seconds in it
was compiling normally (117 MB resident); by 2 minutes 26 seconds it had
made zero further progress -- identical RSS, 0.0% CPU, log unchanged --
while `uptime` reported a load average of 9.0 and a sibling session's own
`run-tests.lisp` held 125% CPU, consistent with host contention. It was left
running and re-checked at 6 minutes 31 seconds: still zero progress, even
though load average had by then dropped to 4.0 -- a real contention-bound
process should have picked up at least some work as load fell, so `sample`
was run against it directly. Every non-finalizer thread was parked: the
three SBCL worker-pool threads on `_dispatch_semaphore_wait_slow` (routine
for an idle pool, not itself informative), and, more tellingly, the main
thread sampled at the exact same unresolved instruction address in all 2662
sub-samples taken over 3 seconds -- the signature of a blocked wait
primitive, not of CPU-starved forward progress, which would sample across a
spread of addresses as it advances. The evidence points to `sb-cover`
instrumentation combined with this machine's SBCL 2.6.6 (`nix develop`'s
pinned toolchain, newer than the bare `sbcl` on this machine's `$PATH`,
2.6.0) deadlocking outright during the instrumented recompile, rather than
merely losing a CPU scheduling race -- host contention from concurrently
running sibling nerima-lisp sessions may still be a contributing factor (it
was present for the first observation), but is not sufficient on its own to
explain zero progress across a load-average drop. The process was killed
rather than left to consume memory indefinitely once this was established.
`nix build`'s sandboxed, single-purpose test derivation does not hit this
path (it never instruments with `sb-cover`), which is why it is the gate
instead of `scripts/run-coverage.lisp`. The script exists and produces an
HTML report when it does complete; it is not run as part of the gate, and no
numeric coverage target is enforced. This is a known gap, not a silent one
-- closing it needs someone to reproduce the deadlock with `sb-cover`
debugging enabled (or on a different SBCL build) to find the actual blocked
resource, which is beyond what this session's tooling could determine.

## Timeout discipline

Every blocking `rt-*-wait`/`-lock`/`-recv`/`-join`/`-await` primitive in
`src/` was swept for a missing or non-functional bound, across two passes.

The first pass found `rt-token-bucket-wait` (no timeout parameter at all --
an oversized or too-fast request spun forever) and `rt-await`/`rt-await*`
(accepted a `:timeout` its polling loop silently ignored, so every caller
through `rt-fiber-await` had a broken timeout guarantee).

A second, deeper pass -- prompted by finding that `rt-with-mutex` and three
sibling macros ran their body even when lock acquisition timed out (see
below) -- found that the initial "already accepted and honored `:timeout`"
read on `rt-semaphore-wait`, `rt-barrier-wait`, and `rt-rwlock-read-lock`/
`-write-lock` was wrong: each re-passed the caller's original `:timeout` to
every retry inside its wait loop instead of a shrinking remaining duration,
so the effective wait could run for an unbounded multiple of the requested
timeout. `rt-semaphore-wait` was worse still -- its inner wait took no
timeout argument at all. `rt-channel-send`/`rt-channel-recv` had the same
defect across their (up to three) wait phases, and a subsequent grep of
every `:timeout` use in `src/` -- rather than trusting the file-by-file
sweep had been exhaustive -- found the identical defect in
`rt-rcu-synchronize`. `rt-actor-receive` and the new opt-in
`rt-actor-send` mailbox-limit wait (see below) share it too. All of these
now share a `deadline computed once, remaining time recomputed per
iteration` helper, `rt-with-remaining-timeout`, extracted from the one
place that already had this right, `rt-future-await`. Every fix in every
pass carries a regression
test that bounds real elapsed time, not just the return value, so a
re-introduced infinite or over-long loop fails the test rather than only the
assertion.

Two blocking paths were reviewed and deliberately left without a timeout
parameter, because adding one would be wrong, not because they were missed:
`rt-socket-send`/`rt-socket-recv` mirror raw BSD socket semantics, and the
multiplexed alternative (`rt-set-nonblocking` with `rt-select`/
`rt-epoll-wait`) already exists for callers that need a bound; `rt-fork-join`
waits on caller-supplied work, and a task that never completes is a caller
bug the primitive cannot paper over without changing what "join" means.

A related but distinct defect surfaced during the same investigation:
`rt-with-mutex`, `rt-with-recursive-mutex`, `rt-with-read-lock` and
`rt-with-write-lock` ran their body -- and unconditionally released the
lock afterward -- even when the underlying `:timeout` expired without the
lock ever being acquired, so a timed-out caller executed its "protected"
section with no mutual exclusion in effect. This is not a missing timeout;
it is a timeout whose expiry silently defeated the very primitive it was
guarding. Fixed by gating body execution on the lock call's actual return
value, matching the one sibling macro (`rt-with-try-mutex`) that already
did this correctly.

`rt-actor-send` also gained an opt-in `:mailbox-limit` (default `nil`,
unbounded, unchanged from before): with it set, a send blocks for room
using the same `rt-with-remaining-timeout` deadline tracking rather than
growing the mailbox without bound under a producer faster than its
consumer. Opt-in rather than a new default, since a default limit would be
a breaking behavior change for every existing caller.

## Error handling

Every condition this library signals derives from `rt-runtime-condition` (or
`rt-runtime-error` for the error subset), so a caller can catch anything from
`cl-cc/runtime` with one `handler-case` clause -- see
[Conditions](conditions.md) for the full catalogue. The runtime also
implements its own independent condition/handler/restart system
(`rt-signal`, `rt-establish-handler`, `rt-restart-case`, ...) for the
*compiled target program's* error handling, deliberately separate from the
host Lisp's, because the source language's semantics need not match Common
Lisp's.

## Concurrency safety

Four safe-memory-reclamation schemes (epoch-based, hazard pointers, RCU,
QSBR), a wait-for-graph deadlock detector (`rt-deadlock-detect`), and a
software-simulated sanitizer layer (`heap-sanitizer.lisp`: ASan/TSan/
HWASan/UBSan-*like* checks against the managed heap's own bookkeeping, not
a hardware sanitizer) are opt-in and disabled by default, for use during
development and in the test suite rather than as an always-on production
cost. `t/heap-sanitizer-test.lisp` runs `it-sequential` (ordering matters:
these tests share detector state) against deliberately corrupted access
patterns to confirm each detector actually flags them.

## Observability

Structured logging (`cl-log-kit`, used directly -- see
[Architecture](architecture.md)), OpenTelemetry spans and metrics export,
Prometheus-format metrics, continuous profiling with OTel/pprof-JSON
rendering, and hardware performance counters are all present and exercised
by tests. `rt-context-spawn` propagates both the runtime's own cancellation/
deadline/value context and cl-log-kit's structured logging context/span id
across the green-thread queue boundary, so a log line inside spawned work
carries the same fields as the code that spawned it.

## Dependency and build hygiene

Three sibling systems (`cl-log-kit`, `cl-process-kit`, `cl-json-kit`), all
used directly with no adapter layer, pinned to release tags rather than a
branch. `:version` in `cl-cc-runtime.asd` is the single source of truth;
`flake.nix` reads it, and the release workflow refuses to publish a tag that
disagrees with it. `nix flake check` is the whole gate -- compile and test,
`nix fmt` formatting, and a strict `mkdocs build` -- run as three parallel
derivations rather than separate CI jobs, so there is one command that
either passes or says exactly why not.

Nine further nerima-lisp org packages were evaluated for adoption over the
course of this refactor (`cl-dataflow`, `cl-parser-kit`, `cl-cli`,
`cl-tty-kit`, `cl-regex-kit`, `cl-history-kit`, `cl-date-kit`,
`cl-concurrent-kit`, `cl-host-kit`); see
[Architecture](architecture.md#why-not-cl-dataflow) and
[Architecture](architecture.md#other-org-packages-evaluated-and-declined)
for the reasoning behind declining all nine as dependencies, and the one
place (`rt-getenv`/`rt-setenv`/`rt-unsetenv`'s POSIX name validation) where
the right answer per the org's own `DEPENDENCY_POLICY.md` was to duplicate
a small, spec-fixed implementation rather than add one.

## Backward compatibility

The one significant compatibility shim this codebase carried -- `t/package.lisp`'s
`deftest`/`assert-*`/`in-suite` vocabulary, re-expressing an older monorepo
test-writing style on top of cl-weave -- was removed; every call site across
`t/` uses cl-weave's native vocabulary directly. A repository-wide sweep for
`deprecated`/`legacy`/`backward-compat`/`TODO`/`FIXME`/`XXX` markers in `src/`
turned up one docstring using "legacy" to describe a current, supported code
path (`rt-allocate-code-memory-xom-aware`'s non-XOM fallback) rather than an
actual compatibility shim; the wording was corrected rather than the code,
since the code itself was correct.

## Known limitations

- No numeric line/branch coverage figure is enforced or currently reported
  (see Correctness and testing above).
- The default green-thread scheduler is cooperative and single-native-thread;
  throughput under real parallelism requires opting into the work-stealing
  scheduler or native threads explicitly (see
  [Core Concepts](core-concepts.md#concurrency-is-cooperative-by-default)).
- Mutation testing currently covers one function, the org's stated floor,
  not the full `src/` tree.
- No numeric bound on how many other org packages, dependency-upgrade
  features, or `src/` functions have been individually audited for the
  same class of defect this session's timeout sweep found (a mutual-
  exclusion bug in four `rt-with-*` macros, six re-armed-timeout wait
  loops, missing exports, dead top-level forms). Each pass that looked
  systematically at one subsystem found something real; the absence of a
  finding in an unaudited subsystem is not evidence of its absence.
