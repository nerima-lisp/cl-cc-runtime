# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `rt-make-actor` accepts an opt-in `:mailbox-limit`; with it set,
  `rt-actor-send` blocks (bounded by its own `:timeout`, using the same
  `rt-with-remaining-timeout` deadline tracking as the sync-primitive fixes
  in `### Fixed` below) for mailbox room rather than growing the mailbox
  without bound under a producer faster than its consumer. Default `nil`
  keeps the mailbox unbounded, matching prior behavior for every existing
  caller. `rt-actor-receive`'s own wait loop had the same re-armed-timeout
  defect as the sync primitives below and is fixed the same way. Closes the
  "unbounded actor mailbox" item `production-readiness.md`'s first audit
  pass had left open.
- `docs/src/production-readiness.md`: a written production-readiness audit
  against concrete criteria (testing depth, timeout discipline, error
  handling, concurrency safety, observability, dependency hygiene, backward
  compatibility), including an honest "Known limitations" section rather
  than a checklist with no way to fail. Linked from the docs home page and
  the `mkdocs.yml` nav.
- `rt-context-spawn` (`context.lisp`) now propagates cl-log-kit's structured
  logging context and span id into the spawned green thread alongside the
  runtime's own `rt-context`, using `capture-log-context` and
  `with-captured-log-context` -- the exact cross-execution-boundary problem
  cl-log-kit's own docstrings describe for `sb-thread:make-thread` applies
  equally to `rt-spawn`'s queued thunk, which runs from a different point on
  the call stack than the call that queued it. `make-function-handler` and
  `log-record-fields` are now imported and re-exported alongside the rest of
  the cl-log-kit surface, so a caller can wire a custom log sink the same
  way the new test in `t/context-test.lisp` observes propagated fields.
- `t/mutation-test.lisp`: mutation-testing coverage (via
  `cl-weave:run-mutations`/`assert-mutation-score`) for
  `rt-return-address-poisoned-p`, satisfying the org's floor of at least one
  mutation-tested function per repository at a score of 1.0. The function
  body is read live from `src/runtime-stack.lisp` on every run, so it cannot
  fall out of sync with the real implementation.
- Test suites across the runtime, and the largest modules split into
  single-concern source files.
- `rt-async-cps-transform` (the async/await CPS transformer in `async.lisp`)
  now handles `when`, `unless`, and `cond` by desugaring to the `if`/`progn`
  cases it already transformed, instead of leaving them in direct style.
- A "Why fiber/event-loop/effects don't use the async CPS transform" section
  in `docs/src/architecture.md`, documenting why `fiber.lisp`'s cooperative
  poll-based await, `effects.lisp`'s restart-based handler resumption, and
  `event-loop.lisp`'s persistent callback registrations are each already the
  correct idiom for their concurrency model rather than gaps to convert to
  `rt-async-cps-transform` -- routing fiber awaits through `rt-future-then`
  would deadlock the single-native-thread cooperative scheduler.
- A package-wide condition hierarchy: `rt-runtime-condition` and
  `rt-runtime-error` are now the base of every condition this system signals,
  so a caller can catch anything from `cl-cc/runtime` with a single
  `handler-case` clause. The six existing condition types now derive from it.
- A documentation site under `docs/`, published with Material for MkDocs.
- `docs.yml`, `release.yml` and `flake-update.yml` workflows, and a shared
  `nix-setup` composite action.
- `checks.formatting` (treefmt/nixfmt) and `checks.docs`
  (`mkdocs build --strict`) in the flake, plus `apps.test`.

- The `deftest`/`deftest-each`/`assert-*`/`in-suite`/`defsuite`/`defbefore`
  compatibility shim from `t/package.lisp` that re-expressed an older
  monorepo test-writing style on top of cl-weave. Every one of the roughly
  2000 call sites across all 65 files in `t/` now uses cl-weave's native
  vocabulary directly (`it-sequential`, `it-sequential-each`, `expect`)
  instead of going through the shim, and human-authored docstrings — which
  the old `deftest` macro silently discarded in favor of a mechanically
  downcased symbol name — are now the displayed test description, matching
  the org's test-naming convention (an assertive English sentence, not an
  identifier).
- 25 internal (unexported) functions and macros across the GC and heap
  modules with zero call sites anywhere in this repository's `src/`, `t/`, or
  any downstream nerima-lisp repository (`cl-cc`, `cl-cc-ast`, `cl-cc-binary`,
  `cl-cc-bootstrap`, `cl-cc-codegen-native`, `cl-cc-javascript`,
  `cl-cc-optimize`, `cl-cc-php`, `cl-cc-type`, `cl-cc-vm`, all checked
  directly). Found with `paredit inspect unused-definitions` and removed with
  `paredit refactor remove-definition`.

### Evaluated and declined

- Ran `paredit inspect duplicates` across all of `src/` (9348 forms, 1524
  groups) and filtered by node-count times occurrence-count to separate
  substantial duplication from the incidental repetition every codebase
  has (`(gethash key table)`-shaped forms recur hundreds of times and mean
  nothing). Found exactly one large genuine match: `rt-sha256`'s and
  `rt-sha512`'s 64/80-round compression loops share the same 242-node
  Davies-Meyer shape. Documented in `crypto.lisp` rather than merged behind
  a parameterized macro -- each function currently reads as a direct,
  line-by-line transcription of its own FIPS 180-4 section, which is worth
  more for hash-function code than the DRY consolidation would be worth.
  Two smaller pairs (`image-core.lisp`'s compress/decompress dispatch,
  `mmap.lisp`'s native-to-buffer/buffer-to-native copies) are naturally
  symmetric read/write or encode/decode shapes at 4-6 lines each, where a
  shared macro would cost more clarity than the few lines it would save.
- Eight further nerima-lisp org packages (`cl-parser-kit`, `cl-cli`,
  `cl-tty-kit`, `cl-regex-kit`, `cl-history-kit`, `cl-date-kit`,
  `cl-concurrent-kit`, `cl-host-kit`) were read and checked against this
  system's actual needs, following `cl-dataflow`'s evaluation earlier in this
  changelog. `cl-parser-kit`/`cl-cli`/`cl-tty-kit`/`cl-history-kit` solve
  problems this runtime library does not have (text parsing, CLI dispatch,
  terminal UI, interactive command recall). `cl-date-kit`'s calendar/IANA
  timezone arithmetic has no consumer here; every clock read in this tree is
  `rt-gettime-monotonic`. `cl-regex-kit` has no string-pattern-matching call
  site to replace. `cl-concurrent-kit` is the same "adjacent layer, wrong
  shape" case as `cl-dataflow`: it offers a bordeaux-threads-style portable
  primitive set, but this system's `sync.lisp` primitives are named `rt-*`
  because the compiler back end emits calls to them by that name, not
  because the runtime lacks a threading facade -- adopting it would mean
  either an adapter over its API or a compatibility-breaking rename of the
  ABI surface this library exists to provide. `cl-host-kit` was the closest
  fit (its `getenv`/`setenv` validate POSIX name syntax, which `os.lisp`'s
  `rt-getenv`/`rt-setenv` did not), but at 2-3 symbols and under 20 lines of
  real logic it falls inside `DEPENDENCY_POLICY.md`'s "duplicate a small,
  spec-fixed implementation rather than add a dependency" rule rather than
  its "add the dependency" path -- see the `rt-getenv`/`rt-setenv`/
  `rt-unsetenv` entry below.

### Changed

- `rt-gc-minor-collect` (`gc-minor.lisp`), the single most complex function
  in the tree by size, had five separate root-scanning blocks (registered
  root cells, dynamic-binding-stack entries, the global-variable registry,
  conservative stack words, stack-map frames) each hand-inlining the same
  "find the address this value points to in the evacuation source, copy the
  referent, rebox to the new address" step. Extracted into one local
  `evacuate` closure shared by four of the five blocks. The fifth
  (stack-map frames) keeps its own inline mapper: `rt-gc-update-stackmap-frame`'s
  callback contract is "return NIL to leave the slot alone," the opposite of
  `evacuate`'s "return the value unchanged when nothing moved," so reusing
  it there would have silently changed behavior -- caught by reading that
  function's implementation before assuming the refactor was uniform, not
  by a test failure. Two of the four now-shared call sites (the dynamic
  binding stack and the global-variable registry) had no direct minor-GC
  test coverage before this change; new tests in `t/gc-minor-test.lisp`
  construct a realistic root of each kind and confirm the shared helper
  evacuates it correctly, closing a real coverage gap the refactor would
  otherwise have relied on manual reasoning alone to justify.
- 49 hand-rolled `(expect (handler-case (progn EXPR nil) (CONDITION-TYPE () t))
  :to-be-truthy)` error-expectation blocks across 20 test files, found via
  `paredit inspect duplicates`, are now `(signals CONDITION-TYPE EXPR)` --
  cl-weave's own purpose-built macro for exactly this check, discovered
  earlier in this changelog's env-var-validation tests but not until now
  applied to the rest of the suite. Applied via `paredit query replace` in
  two passes (generic `error`, then an arbitrary condition-type symbol),
  each verified with `--diff` before `--write`.
  One of the 50 mechanically-identical-looking matches was not actually
  safe to convert: `perf-counters-unsupported` derives from
  `rt-runtime-condition`, not `error` (see `conditions.md`), and
  cl-weave's `signals`/`:to-throw` only catches `error` subtypes internally
  -- converting it silently broke the test, which then crashed the whole
  suite with an unhandled condition instead of failing one assertion. The
  full-suite run after the mechanical pass caught it immediately; reverted
  that one case to `handler-case` with a comment explaining why, and
  audited every other converted condition type's class hierarchy
  (`type-error`, `rt-effect-condition`, `rt-stack-overflow`) to confirm
  none of the surviving 49 share the same defect.
- Five byte-identical copies of a "resolve an SB-THREAD function by name, or
  NIL when SB-THREAD is unavailable" helper -- one each in
  `heap-sanitizer.lisp`, `gc-tlab.lisp`, `gc-write-barrier.lisp`,
  `gc-major-mark.lisp` and `gc-workers.lisp`, plus two further ad hoc call
  sites in `gc-concurrent-sweep.lisp` -- are now the one
  `%rt-resolve-sb-thread-function`, defined once in `heap-sanitizer.lisp`
  (the earliest of those files in the `.asd` load order) and called from
  the rest. The five lock-scoping macros built on top of those copies
  (`%rt-with-sanitizer-map-lock`, `%rt-gc-with-tlab-refill-lock`,
  `with-gc-satb-thread-queues-locked`, `with-gc-mark-queue-locked`,
  `%rt-gc-with-optional-mutex`) split into two genuinely distinct shapes --
  CALL-WITH-MUTEX-based and GRAB-MUTEX/RELEASE-MUTEX-based -- each now a
  thin one-line wrapper around a new shared macro for its shape,
  `%rt-with-optional-lock` and `%rt-with-optional-grab-release-lock`
  respectively, parameterized on the lock place instead of each hardcoding
  its own. Zero behavior change; found by reading the four
  near-identically-shaped "optional lock" macros side by side after
  `sync.lisp`'s bugs made this class of pattern worth looking for
  elsewhere in the tree.
- `rt-getenv`, `rt-setenv` and `rt-unsetenv` (`os.lisp`) now reject a
  syntactically invalid environment variable name (empty, or containing `=`
  or NUL) before it reaches `sb-ext:posix-getenv`/`sb-posix:setenv`/
  `sb-posix:unsetenv`, instead of passing it straight through to the host
  and risking a silently truncated or corrupted environment write. The check
  is a small, sourced duplication of `cl-host-kit`'s
  `HOST-KIT::%ENVIRONMENT-VARIABLE-NAME-P` -- evaluated and declined as a new
  dependency (see `### Evaluated and declined` below) because POSIX's
  environment-variable name grammar is a fixed spec and the whole
  implementation is under 20 lines, which is exactly the case
  `DEPENDENCY_POLICY.md`'s "duplicate before depending" rule covers.
- `flake.nix` now generates its whole output table from
  `cl-nix-forge.lib.${system}.mkPackageFlake` instead of hand-rolling
  `packages`/`checks`/`apps`/`devShells`, cutting it from roughly 320 lines to
  a single declarative call and bringing it in line with the other 20
  repositories in the org.
- `rt-heap-ref` and `rt-heap-set` shared their four-sanitizer check preamble
  (UBSan, ASan, HWASan, TSan) through a new `%rt-sanitizer-check-heap-access`
  macro in `heap-sanitizer.lisp` instead of repeating it at both call sites.
- `rt-condition-wait`'s bare `1e6`-second fallback timeout is now the named
  constant `+rt-condition-wait-default-timeout-seconds+` in `sync.lisp`, with
  a docstring explaining why this one primitive always passes SB-THREAD a
  finite timeout while `rt-mutex-lock`/`rt-thread-join` block indefinitely
  when theirs is omitted.
- `continuous-profile.lisp` (472 lines) split into the sampling engine and a
  new `continuous-profile-export.lisp` (JSON, OTel profiles signal, and
  pprof-JSON encodings), following the org's file-length guidance.
- `image-core.lisp` (467 lines) split into binary buffer/compression/token
  primitives, a new `image-core-graph.lisp` (object-graph encode/decode), and
  a new `image-core-persist.lisp` (the core image file format and
  `rt-save-core`/`rt-load-core`).
- `gc-roots-objects.lisp` (439 lines) split into pointer/root classification
  and the root registry, a new `gc-stackmaps.lisp` (stackmap scanning), a new
  `gc-binding-scan.lisp` (dynamic binding-stack and global-variable
  scanning), a new `gc-heap-verify.lisp` (`rt-gc-verify-heap`), and a new
  `gc-alloc.lisp` (young/old bump allocation).
- `reactive.lisp` (424 lines) split into the Reactive Streams
  subscription/subscriber protocol and a new `reactive-publishers.lisp`
  (the list/map/filter/merge/zip publisher implementations).
- `gc-major-sweep.lisp` (409 lines) split into the sweep pass and three new
  files: `gc-compact.lisp` (old-space compaction), `gc-concurrent-sweep.lisp`
  (the background worker sweep), and `gc-major-collect.lisp` (the top-level
  major-GC orchestrator).
- `value.lisp` (385 lines) split along a data/logic line: the NaN-boxed
  tag/mask layout constants moved to a new `value-tags.lisp` (pure data),
  and the pinned unboxed-array buffers (a distinct FFI concern needing the
  pointer codec) moved to a new `value-pinned-array.lisp`, leaving `value.lisp`
  itself as the predicates and encoders that operate on the tag layout.
- `runtime-math-io.lisp` (368 lines) split into symbol plists/arithmetic/
  signals/misc primitives, a new `runtime-weak-hash-table.lisp`
  (`rt-make-hash-table` and weak-hash-table support), and a new
  `runtime-dynamic-binding.lisp` (special-variable registration and the
  dynamic binding stack).
- `runtime-clos-dispatch.lisp` (353 lines) split into the generic-function
  and method registry, a new `runtime-clos-applicability.lisp`
  (`rt-compute-applicable-methods`), and a new `runtime-clos-invoke.lisp`
  (`rt-call-generic` and method combination).
- `crypto.lisp` (335 lines) split into SHA-256/SHA-512/HMAC-SHA256 and a new
  `crypto-base64.lisp` (RFC 4648 Base64), an unrelated encoding rather than a
  hash.
- `gc-tlab.lisp` (329 lines) split into thread-local allocation buffers and
  a new `gc-copy.lisp` (the Cheney-scan object copying the minor-GC scanner
  uses).
- `gc-policy.lisp` (323 lines) split into GC pause/pacer policy and a new
  `gc-pinning.lisp` (object pinning for FFI).
- `ffi.lisp` (322 lines) split into the native FFI (calling out to C) and a
  new `ffi-embedding-api.lisp` (the `cl-cc-*` C embedding API, the reverse
  direction: letting C call into this runtime).
- `runtime-conditions.lisp` (308 lines) split into the condition base types
  and the handler/restart system, and a new `runtime-code-cache.lisp` (the
  JIT code cache, which had no thematic relation to the rest of the file).
- `serialize.lisp` (310 lines) split into the wire-format tags/context and
  the serialization (write) path, and a new `deserialize.lisp` (the
  deserialization/read path).
- `heap-access.lisp` (352 lines) split into heap construction and the core
  word read/write primitives, a new `heap-forwarding.lisp` (concurrent
  relocation and compressed pointers), a new `heap-numa.lisp` (NUMA-aware
  allocation), and a new `heap-stats.lisp` (occupancy/fragmentation queries).
- `gc-major-mark.lisp` (398 lines) split into concurrent-mark configuration
  and mode control, and a new `gc-mark-work.lisp` (root seeding, grey-set
  draining, and the concurrent mark worker).
- `gc-references.lisp` (394 lines) split into the soft/weak/phantom
  reference and hash-consing primitives, and a new `gc-weak-processing.lisp`
  (ephemerons, weak hash tables, and the GC-time processing passes over
  them).
- `topology.lisp` (407 lines) split into CPU core-count detection and a new
  `topology-numa-memory.lisp` (NUMA topology, CPU affinity masks, and memory
  tier detection), resolving a mutual dependency between the CPU-affinity
  alien-routine helpers and `get-cpu-affinity-mask`/`set-cpu-affinity-mask`
  by moving the whole affinity apparatus into the new file together.
- `scheduler.lisp` (410 lines) split into the cooperative green-thread
  scheduler and three new files: `scheduler-work-stealing.lisp` (the
  work-stealing parallel scheduler), `scheduler-native-thread.lisp` (the
  native OS thread wrapper), and `scheduler-thread-pool.lisp` (the fixed-size
  thread pool built on it).
- Sibling package pins bumped to their latest released tags: `cl-weave`
  v1.0.0 -> v1.1.0, `cl-log-kit` v1.0.0 -> v2.0.0, `cl-json-kit` v1.0.0 ->
  v1.0.1, `cl-boundary-kit` v0.6.0 -> v1.0.0 (now resolved transitively
  through `cl-process-kit`'s own dependency closure rather than as a direct
  flake input), and `cl-process-kit` v1.0.1 -> v2.0.0. Neither
  `cl-log-kit`'s `rotating-file-handler` UTC-bucketing change nor
  `cl-process-kit`'s `next-process-event` struct-return change is used by
  this codebase.
- The test system moved from a separate `cl-cc-runtime-test.asd` into
  `cl-cc-runtime.asd` as `cl-cc-runtime/test`.
- Tests moved from `tests/` to `t/`, and the test entry point from
  `scripts/run-tests.lisp` to `run-tests.lisp`.
- Dependencies are located through `CL_SOURCE_REGISTRY` instead of five
  bespoke `CL_CC_RUNTIME_<NAME>_ROOT` environment variables.
- Sibling flake inputs are pinned to release tags, and the package version is
  read from `cl-cc-runtime.asd` rather than hardcoded in `flake.nix`.
- `flake.nix` tracks `nixos-unstable` and declares `x86_64-linux` and
  `aarch64-darwin` only. `aarch64-linux` and `x86_64-darwin` were declared but
  never built.

### Fixed

- `t/async-test.lisp` and `t/scheduler-test.lisp` each defined
  `with-fresh-scheduler`, a test helper binding a fresh scheduler for test
  isolation, with different bodies: `scheduler-test.lisp`'s (loaded first
  per the `.asd`) also reset `*rt-current-green-thread*`, `async-test.lisp`'s
  did not. Because `async-test.lisp` loads second, its narrower version
  silently shadowed the fuller one for its own tests below the
  redefinition -- a real, if narrow, test-isolation gap, not just
  duplication. Found via `paredit inspect duplicates`, which flagged the
  two as *not* matching (different bodies) where a first glance at the
  name suggested they should. Removed the redundant narrower copy so
  `async-test.lisp` inherits `scheduler-test.lisp`'s fuller definition.
- `rt-rcu-synchronize` (`rcu.lisp`) had the same re-armed-timeout defect as
  the six `sync.lisp`/`channel.lisp` functions below: it re-passed the
  caller's original `:timeout` to every `rt-condition-wait` in its
  wait-for-readers-to-drain loop instead of a shrinking remaining duration.
  Found by grepping every `src/` file for `:timeout` usage rather than
  trusting the earlier file-by-file sweep had been exhaustive -- it hadn't.
  Fixed with the same `rt-with-remaining-timeout` helper, with a new
  regression test bounding real elapsed time in `t/rcu-test.lisp`.
- **`rt-with-mutex`, `rt-with-recursive-mutex`, `rt-with-read-lock` and
  `rt-with-write-lock` (`sync.lisp`) ran their body -- and unconditionally
  released the lock afterward -- even when a caller-supplied `:timeout`
  expired without the lock ever being acquired.** Each macro discarded its
  underlying `rt-*-lock` call's return value instead of gating on it, so a
  timed-out caller executed its "protected" critical section with no mutual
  exclusion in effect at all, then called unlock on a lock it had never
  taken. `rt-with-try-mutex` already had the correct gate-on-acquisition
  shape; the other four now match it. Caught by empirically confirming
  SBCL's `grab-mutex`/`release-mutex` semantics (`sb-thread:release-mutex`
  on an unheld mutex is a safe no-op on this SBCL version, so the exposure
  was unsynchronized body execution, not a force-unlock of another thread's
  critical section) before writing the fix, and a new real-thread regression
  test in `t/sync-test.lisp` proves the body no longer runs while another
  thread holds the lock.
- `rt-semaphore-wait`, `rt-barrier-wait`, `rt-rwlock-read-lock` and
  `rt-rwlock-write-lock` (`sync.lisp`), and `rt-channel-send`/
  `rt-channel-recv` (`channel.lisp`), re-passed the caller's original
  `:timeout` to every `rt-condition-wait` call inside their retry loops
  instead of a shrinking remaining duration, so a spurious wakeup or an
  unmet condition re-armed the full budget on every iteration -- the
  effective wait could run for an unbounded multiple of `:timeout` rather
  than `:timeout` itself. `rt-semaphore-wait` was worse: its inner wait took
  no timeout argument at all, so `:timeout` bounded only the initial lock
  acquisition, never the actual wait for a permit. Fixed by extracting the
  deadline-tracking shape `rt-future-await` already had correct
  (`get-internal-real-time` deadline, shrinking remaining-seconds per
  iteration) into a new shared `rt-with-remaining-timeout` macro in
  `sync.lisp`, applied to all six functions -- turning a real, repeated bug
  into the macro consolidation this refactor's goal asked for. New
  regression tests in `t/sync-test.lisp` and `t/channel-test.lisp` bound
  real elapsed time for each, so a re-introduced re-armed-timeout loop fails
  the test rather than only the return value.
- `rt-with-mutex`, `rt-condition-wait`, `rt-condition-notify`,
  `rt-condition-notify-all`, `rt-mutex-try-lock`, `rt-with-try-mutex`,
  `rt-mutex-owner`, and the new `rt-with-remaining-timeout` were usable
  throughout `src/` but not exported from `cl-cc/runtime` -- `rt-with-mutex`
  in particular is the primary safe, scoped way to use a mutex and was
  reachable only via the internal `cl-cc/runtime::` prefix, and a condition
  variable could be waited on (`rt-condition-wait-until`, itself built on
  the unexported `rt-condition-wait`) but never notified by any external
  caller. Now exported, matching the sibling `rt-with-recursive-mutex`/
  `rt-with-read-lock`/`rt-with-write-lock`/`rt-recursive-mutex-try-lock`/
  `rt-rwlock-try-read-lock`/`rt-rwlock-try-write-lock` that already were.
- Six bare, unparenthesized `progn` tokens -- syntactically valid but
  meaningless top-level forms, each evaluated as an undefined-variable
  reference to `COMMON-LISP:PROGN` and warned about on every compile --
  were left behind by an earlier mechanical edit this session, in
  `src/stm.lisp`, `src/async-generators.lisp`, `t/stm-test.lisp`,
  `t/channel-test.lisp` (two) and `t/async-generators-test.lisp`. Found by
  reading full build-log warnings rather than only the pass/fail summary,
  and removed; a full rebuild now compiles with zero warnings.
- `*rt-global-scheduler*` was referenced in `scheduler.lisp` (`rt-yield`,
  `rt-spawn`, `rt-scheduler-init`) but only `defvar`'d in
  `scheduler-work-stealing.lisp`, which loads after it in the `.asd` --
  introduced when `scheduler.lisp` was split earlier this session and the
  `defvar` ended up in the wrong output file. SBCL treated every
  `scheduler.lisp` reference as an undefined-variable forward use; harmless
  in practice since the `defvar` still ran before any code executed, but a
  real hygiene defect and a warning on every compile. Moved the `defvar` to
  `scheduler.lisp`, where the variable is actually used and conceptually
  belongs.
- A repository-wide sweep of `src/` for `deprecated`/`legacy`/
  `backward-compat`/`TODO`/`FIXME`/`XXX` markers, run to verify the backward-
  compatibility elimination this refactor asked for actually holds, found
  one docstring (`rt-allocate-code-memory-xom-aware` in `xom.lisp`) calling
  the non-XOM allocation path "legacy mmap" when it is a current, supported
  fallback mode, not a compatibility shim. Reworded rather than changed the
  code, which was already correct.
- `rt-await*`/`rt-await` (`async.lisp`) accepted a `:timeout` argument but
  silently ignored it: the polling loop that cooperatively yields while
  waiting for a future checked only whether the future had resolved, never
  the deadline, so it span until the future resolved no matter what timeout
  was requested. `RT-FUTURE-AWAIT`'s own timeout logic, at the end of the
  function, was only reachable once that loop had already exited by the
  future resolving on its own -- by which point the timeout it was given
  could never fire. Found by the same "always set an appropriate command
  timeout" sweep that fixed `rt-token-bucket-wait` above; every consumer of
  `rt-await` with a `:timeout` (including `rt-fiber-await`) had this same
  silent-ignore bug. The poll loop now tracks its own deadline and clamps
  the remaining budget it hands to `rt-future-await`, and a new regression
  test in `t/async-test.lisp` bounds real elapsed time so a re-introduced
  infinite loop fails the test instead of only the return value.
- `rt-token-bucket-wait` (`ratelimit.lisp`) had no way to bound its wait: it
  spun on `try-acquire`/`sleep` forever, which never terminates when the
  caller asks for more tokens than the bucket's `burst` ever holds, or
  simply requests faster than `rate` replenishes. It now accepts a
  `:timeout` (seconds) and returns `nil` once that budget is spent instead
  of blocking indefinitely -- audited into existence by the standing
  refactor goal's "always set an appropriate command timeout" item, which
  prompted a sweep of every `rt-*-wait`/`-lock`/`-recv`/`-join`/`-await`
  primitive in `src/` for one missing a bound. The first implementation
  checked the deadline only between sleeps without capping each sleep's own
  length, so a low-`rate` bucket could still overshoot a short `:timeout` by
  a full refill interval; the fix clamps each sleep to whichever is
  smaller, the natural refill interval or the time left before the
  deadline. New tests in `t/ratelimit-test.lisp` cover both the success and
  timeout-expiry paths.
- `docs/src/core-concepts.md` pointed at "the native-thread section of
  `scheduler.lisp`" for native OS threads; that section was split into
  `scheduler-native-thread.lisp` earlier in this refactor and the page had
  not been updated. Also tightened its `value.lisp` reference to name
  `value-tags.lisp` and `value-codec.lisp`, its constant/codec split.

- `rt-base64-decode` indexed a 128-entry ASCII lookup table with a
  character's raw code point with no range check, so any input containing a
  codepoint past ASCII (anything from Latin-1 supplement upward) signalled an
  out-of-bounds array access instead of treating it as "not in the alphabet"
  the way every other non-alphabet character already was. Found while adding
  `t/mutation-test.lisp`-style advanced cl-weave coverage: an `it-fuzz` test
  generating strings from an alphabet including a few deliberately
  out-of-ASCII-range codepoints now guards this file, alongside a new
  `it-property` round-trip test replacing the previous fixed-case-only
  coverage for `rt-base64-encode`/`rt-base64-decode`.
- `rt-gc-alloc`'s slab-allocation strategy did not fall back to another
  allocation strategy when the slab pool's page could not grow (old space
  full) as its own comments said it should -- the `cond` clause committed to
  the slab attempt's result unconditionally, including `nil` on failure,
  which a caller would have tried to use as a word address. Only reachable
  when `*rt-use-slab-allocator*` is bound to true (it defaults to `nil`), so
  this had no default-configuration impact, but is fixed to match the
  documented intent, with a regression test forcing the exhaustion path.
  `rt-gc-alloc` itself was also split into four named per-strategy helpers
  (`%rt-gc-alloc-via-slab`, `%rt-gc-alloc-large-object`,
  `%rt-gc-alloc-old-space`, `%rt-gc-alloc-young-space`) while fixing this,
  since the single function mixing all four strategies inline was the reason
  the bug was hard to see in the first place.
- `flake.lock` no longer disagrees with `flake.nix`: it listed two nodes for a
  flake that declared five sibling inputs, so a lock update would have
  resolved dependencies that had never been locked.
- Three `segmented native stack` tests in `t/runtime-stack-test.lisp` assumed
  a 4KB host page size (matching the x86_64-linux CI runner) and silently
  passed there while failing on any 16KB-page host such as aarch64-darwin,
  which the flake declares as a verified platform. `rt-page-align` rounds
  mmap requests up to `+rt-page-size+`, read from the real `getpagesize()` at
  load time, so a segment requested at 8192 bytes is mapped at exactly 8192
  bytes on a 4KB-page host but 16384 on a 16KB-page host — the tests now
  derive their expectations from `rt-page-align` and from each segment's
  actual remaining capacity instead of hardcoding sizes that only held on one
  page size.
- `rt-lower-coroutine`'s `:supports-call/cc` keyword argument was signaling
  `unbound-key` errors on the only test that exercised the stackful-lowering
  path: the parameter was missing the `-p` suffix the org's own naming
  convention requires for boolean flags (`deep-yield-p`, its sibling
  parameter, already had it). Renamed to `:supports-call/cc-p`.

## [0.1.0] - 2026-07-23

### Added

- Initial extraction of the runtime library from the cl-cc monorepo as a
  standalone ASDF system: the `cl-cc/runtime` package, the generational
  garbage collector, heap and allocator, NaN-boxed value representation,
  register frames, images, FFI, and the concurrency primitives.
