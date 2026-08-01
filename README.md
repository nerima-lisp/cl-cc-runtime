# cl-cc-runtime

[![CI](https://github.com/nerima-lisp/cl-cc-runtime/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nerima-lisp/cl-cc-runtime/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-MkDocs%20Material-0a7a5a)](https://nerima-lisp.github.io/cl-cc-runtime/)

cl-cc-runtime is the target runtime that the
[cl-cc](https://github.com/nerima-lisp/cl-cc) compiler emits code against: a
generational garbage collector, a word-addressed managed heap, a NaN-boxed
value representation, register frames, and a large set of concurrency
primitives, all exported from one package for SBCL. It is shaped by what a
code generator needs -- addresses rather than objects, explicit roots rather
than stack scanning -- so it is not a general-purpose concurrency toolkit.

Full documentation is published at <https://nerima-lisp.github.io/cl-cc-runtime/>.
The source for that site lives in [docs/src/](docs/src/).

## Quick Start

Allocate on a managed heap, keep one object reachable, collect, and watch the
survivor move while the garbage is reclaimed:

```lisp
(asdf:load-system "cl-cc-runtime")

(defpackage :runtime-demo (:use :cl :cl-cc/runtime))
(in-package :runtime-demo)

(let* ((heap (make-rt-heap :young-size 64 :old-size 64))
       (addr (rt-gc-alloc heap +rt-tag-cons+ 3))
       (root (cons nil addr)))
  (rt-heap-set-header heap addr (make-rt-header 3 +rt-tag-cons+ :gc-bits 0))
  (rt-heap-set heap (+ addr 1) 111)
  (rt-gc-add-root heap root)
  (rt-gc-alloc heap +rt-tag-cons+ 3)      ; nothing points at this
  (rt-gc-minor-collect heap)
  (list :moved-to (cdr root)
        :value (rt-heap-ref heap (+ (cdr root) 1))
        :collected (getf (rt-gc-stats heap) :words-collected)))
;; => (:MOVED-TO 32 :VALUE 111 :COLLECTED 29)
```

## Install

```nix
# flake.nix
inputs.cl-cc-runtime = {
  url = "github:nerima-lisp/cl-cc-runtime/v0.1.0";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Note the pinned tag. Consumers inside this org must pin a release tag rather
than follow the default branch.

The system depends on [cl-log-kit](https://github.com/nerima-lisp/cl-log-kit),
[cl-process-kit](https://github.com/nerima-lisp/cl-process-kit) and
[cl-json-kit](https://github.com/nerima-lisp/cl-json-kit), and needs
[cl-boundary-kit](https://github.com/nerima-lisp/cl-boundary-kit) on the source
registry as well because cl-process-kit requires it.

## Documentation

- [Getting Started](https://nerima-lisp.github.io/cl-cc-runtime/getting-started/)
- [Core Concepts](https://nerima-lisp.github.io/cl-cc-runtime/guide/core-concepts/)
- [API Reference](https://nerima-lisp.github.io/cl-cc-runtime/reference/api/)
- [Architecture](https://nerima-lisp.github.io/cl-cc-runtime/reference/architecture/)

## Development

```sh
nix develop          # SBCL with CL_SOURCE_REGISTRY already set
nix run .#test       # run the test suite
nix flake check      # tests + formatting + docs, the same gate CI uses
nix fmt              # format Nix sources (treefmt)
```

Tests live in `t/` and run under [cl-weave](https://github.com/nerima-lisp/cl-weave),
the org's test framework. `scripts/run-coverage.lisp` writes an sb-cover report
to `coverage/`.

## Contributing

See the org-wide [CONTRIBUTING](https://github.com/nerima-lisp/.github/blob/main/CONTRIBUTING.md)
guide and the [package standard](https://github.com/nerima-lisp/.github/blob/main/PACKAGE_STANDARD.md).

## Support

See [SUPPORT](https://github.com/nerima-lisp/.github/blob/main/SUPPORT.md).

## License

MIT. See [LICENSE](LICENSE).
