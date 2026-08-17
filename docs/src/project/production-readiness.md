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
time it ran.

At least one function per the org's mutation-testing floor is verified with
`cl-weave:run-mutations`/`assert-mutation-score` at a score of 1.0 (see
[Architecture](../reference/architecture.md#testing)): every single-operator mutation of
that function's real body is caught by its existing case battery, not just
executed by it. This is deeper evidence than line coverage, which this
project does not currently report as a percentage. `scripts/run-coverage.lisp`
exists and produces an HTML report when it completes; it is not run as part
of the gate, and no numeric coverage target is enforced.

This was investigated at length rather than taken on faith, and the
investigation changed the diagnosis. The original claim in this document was
that `sb-cover`'s instrumented recompile itself starves or deadlocks on this
machine; direct measurement does not support that. Bisecting the failure by
running each stage of `scripts/run-coverage.lisp` in isolation (source
registry setup, each dependency load, `sb-cover` instrumentation, the
compile) found that plain `(asdf:load-system "cl-log-kit")` -- no
`sb-cover`, no coverage declaim, nothing project-specific -- already hangs
indefinitely when run as an ordinary `sbcl --script` process, whether or not
that process runs inside `nix develop`'s shell. `asdf:initialize-source-registry`
itself was separately timed at 0.05 seconds, ruling out the `(:tree ...)`
source-registry entry as the cause. A `sample` taken against one such hung
process showed every non-finalizer thread parked -- the main thread at one
identical unresolved instruction address across all 2662 sub-samples taken
over 3 seconds -- consistent with a genuine blocked wait, not scheduling
contention; a follow-up hostname/DNS timing check and a source-level search
of `cl-log-kit` for networking calls both came back clean, so the specific
blocked resource is still unidentified.

The load-bearing fact is narrower than the failure mode: `nix build
.#checks.<system>.default` -- the actual gate -- loads this exact same
`cl-log-kit` dependency as part of running all 1142 tests, and does so
successfully and repeatably (see above). Whatever makes an ad hoc, outside-
the-sandbox `sbcl --script` invocation on this machine hang loading
`cl-log-kit` does not reproduce inside `nix build`'s sandboxed derivation.
`scripts/run-coverage.lisp` was never successfully run to completion in this
investigation as a result, so no numeric coverage figure could be produced
this session -- but the cause is this machine's interactive-shell
environment, not a `cl-cc-runtime`-side or `sb-cover`-side defect, and
specifically not the SBCL-thread-deadlock-during-instrumentation theory this
document previously stated. This is a known gap, not a silent one -- closing
it needs someone to run `scripts/run-coverage.lisp` on a machine where a bare
`sbcl --script` can load `cl-log-kit`, or to root-cause why this machine's
cannot, neither of which this session's tooling could complete.

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
[Conditions](../reference/conditions.md) for the full catalogue. The runtime also
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
[Architecture](../reference/architecture.md)), OpenTelemetry spans and metrics export,
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
course of this refactor (`cl-dataflow-kit`, `cl-parser-kit`, `cl-cli`,
`cl-tty-kit`, `cl-regex-kit`, `cl-history-kit`, `cl-date-kit`,
`cl-concurrent-kit`, `cl-host-kit`); see
[Architecture](../reference/architecture.md#why-not-cl-dataflow-kit) and
[Architecture](../reference/architecture.md#other-org-packages-evaluated-and-declined)
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
  [Core Concepts](../guide/core-concepts.md#concurrency-is-cooperative-by-default)).
- Mutation testing currently covers one function, the org's stated floor,
  not the full `src/` tree.
- No numeric bound on how many other org packages, dependency-upgrade
  features, or `src/` functions have been individually audited for the
  same class of defect this session's timeout sweep found (a mutual-
  exclusion bug in four `rt-with-*` macros, six re-armed-timeout wait
  loops, missing exports, dead top-level forms). Each pass that looked
  systematically at one subsystem found something real; the absence of a
  finding in an unaudited subsystem is not evidence of its absence.
