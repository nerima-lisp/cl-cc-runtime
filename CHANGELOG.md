# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Test suites across the runtime, and the largest modules split into
  single-concern source files.
- A documentation site under `docs/`, published with Material for MkDocs.
- `docs.yml`, `release.yml` and `flake-update.yml` workflows, and a shared
  `nix-setup` composite action.
- `checks.formatting` (treefmt/nixfmt) and `checks.docs`
  (`mkdocs build --strict`) in the flake, plus `apps.test`.

### Changed

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

- `flake.lock` no longer disagrees with `flake.nix`: it listed two nodes for a
  flake that declared five sibling inputs, so a lock update would have
  resolved dependencies that had never been locked.

## [0.1.0] - 2026-07-23

### Added

- Initial extraction of the runtime library from the cl-cc monorepo as a
  standalone ASDF system: the `cl-cc/runtime` package, the generational
  garbage collector, heap and allocator, NaN-boxed value representation,
  register frames, images, FFI, and the concurrency primitives.
