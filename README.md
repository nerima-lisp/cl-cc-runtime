# cl-cc-runtime

Runtime library for the [cl-cc](https://github.com/nerima-lisp/cl-cc) Common
Lisp compiler: the `:cl-cc/runtime` package — the package system, garbage
collector (minor/major, TLAB, write barriers), heap and allocator, value
representation, serialization/images, FFI, and concurrency primitives.

A **dependency-free leaf system** extracted from the cl-cc monorepo as part of
the repository split (see `docs/repo-split-design.md` in cl-cc). This is the
*target runtime* the compiler emits against — largely independent of the
compiler itself, which only consumes the package system.

## Status

Extracted and building standalone, with a cl-weave suite (447 tests). Tests
that drive the runtime from the VM/bytecode layer, do real native `dlopen`, or
exercise crypto/compress implementations that live outside this package stay in
the monorepo. Some concurrency modules (crdt, consensus, gpu, io-uring, …) have
no in-tree consumers yet — see the split design's orphan analysis.

## Usage

```lisp
(asdf:load-system :cl-cc-runtime)
```

## Development

```bash
nix develop
nix flake check        # compile check + cl-weave test suite
```

## License

MIT — see [LICENSE](LICENSE).
