# Development

Everything below assumes a checkout and a working Nix with flakes enabled. The
flake pins SBCL and every sibling dependency, so there is nothing else to
install.

## The gate

```sh
nix flake check --print-build-logs
```

This is exactly what CI runs. It builds three checks in parallel:

| Check | What it does |
|---|---|
| `checks.default` | Compiles `cl-cc-runtime` and runs the cl-weave suite via `run-tests.lisp` |
| `checks.formatting` | Fails when any Nix file is not nixfmt-formatted |
| `checks.docs` | Builds this site with `mkdocs build --strict`, so a broken link or a page missing from the nav fails |

Granularity lives in these attributes rather than in extra GitHub Actions jobs.
`nix flake check` already evaluates each one as its own derivation, in
parallel, with build caching; splitting them into jobs would duplicate that
scheduling and lose the cache between them. If you want a new gate, add a
`checks.*` attribute, not a job.

## Running the tests alone

```sh
nix run .#test
```

Or from a development shell, where `CL_SOURCE_REGISTRY` is already set to the
pinned siblings:

```sh
nix develop
sbcl --script run-tests.lisp
```

`run-tests.lisp` is at the repository root. It registers the checkout and
inherits `CL_SOURCE_REGISTRY` for `cl-weave`, `cl-log-kit`, `cl-process-kit`,
`cl-boundary-kit` and `cl-json-kit`, then calls
`(asdf:test-system "cl-cc-runtime")`.

The suite starts real threads for the lock-free, STM, scheduler and consensus
tests, so it takes noticeably longer than a pure library's and the check
carries a 600-second timeout.

## Compile check only

The fastest way to find out whether a change reads:

```sh
nix develop
sbcl --script scripts/run-compile-check.lisp
```

## Coverage

```sh
nix develop
sbcl --script scripts/run-coverage.lisp
```

This writes an HTML report to `coverage/cover-index.html`. Only `src/` is
instrumented; instrumenting the test system would count the tests themselves as
covered code.

Coverage is not part of `nix flake check`. sb-cover has to recompile every
source file with instrumentation, and the report is something to read rather
than a pass/fail gate. `coverage/` is in `.gitignore`.

## Formatting

```sh
nix fmt
```

treefmt runs nixfmt over the Nix sources, and nothing else. YAML formatters
mangle the GitHub Actions `on:` key, and reformatting Markdown would churn the
whole docs tree; neither is cheap enough to be worth enforcing.

Lisp sources are formatted by hand. The conventions are in the org's
[coding standard](https://github.com/nerima-lisp/.github/blob/main/CODING_STANDARD.md):
100-column lines, roughly 300 lines per file with 500 as the ceiling, `#:`
designators in `defpackage`, and `:use` limited to `#:cl`.

## Building the docs

```sh
nix build .#docs
```

To edit them with live reload, from the repository root:

```sh
mkdocs serve -f docs/mkdocs.yml
```

Run mkdocs from the root, not from `docs/`: `docs/src/changelog.md` includes
the root `CHANGELOG.md` through a snippets include whose base path is the
working directory. Add `--no-strict` while editing if warnings get in the way,
but the committed state has to build with `--strict`.

Every page under `docs/src/` must appear in the `nav` in `docs/mkdocs.yml`.
That is what `--strict` enforces, and it is why the nav cannot quietly fall
behind the tree.

## Releasing

The `:version` in `cl-cc-runtime.asd` is the single source of truth. To cut a
release: update `:version`, move the `## [Unreleased]` entries in
`CHANGELOG.md` under a new `## [X.Y.Z] - YYYY-MM-DD` heading, and push the tag
`vX.Y.Z`.

`release.yml` refuses to publish when the tag and the `.asd` version disagree,
runs `nix flake check` against the tagged tree, and takes the release body from
the matching CHANGELOG section. A heading that deviates from
`## [X.Y.Z] - YYYY-MM-DD` makes that extraction come up empty and fails the
release.

## Keeping dependencies current

`flake-update.yml` opens a pull request every Monday bumping every flake input.
Sibling packages stay pinned to release tags, so that bot only moves nixpkgs
and treefmt-nix; moving to a new sibling release is a deliberate edit to
`flake.nix`.
