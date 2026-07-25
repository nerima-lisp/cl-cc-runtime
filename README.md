# cl-cc-runtime

Runtime library for the [cl-cc](https://github.com/nerima-lisp/cl-cc) Common
Lisp compiler: the `:cl-cc/runtime` package — the package system, garbage
collector (minor/major, TLAB, write barriers), heap and allocator, value
representation, serialization/images, FFI, and concurrency primitives.

A leaf system extracted from the cl-cc monorepo as part of the repository
split (see `docs/repo-split-design.md` in cl-cc). This is the *target
runtime* the compiler emits against — largely independent of the compiler
itself, which only consumes the package system. It builds directly on
sibling [nerima-lisp](https://github.com/orgs/nerima-lisp/repositories)
libraries rather than reimplementing what they already do well: structured
logging ([cl-log-kit](https://github.com/nerima-lisp/cl-log-kit)),
timeout-guarded process execution
([cl-process-kit](https://github.com/nerima-lisp/cl-process-kit)), and JSON
serialization for its OpenTelemetry/pprof export paths
([cl-json-kit](https://github.com/nerima-lisp/cl-json-kit)).

## Status

Extracted and building standalone, with a [cl-weave](https://github.com/nerima-lisp/cl-weave)
suite (1000+ tests, including property-based and real-concurrency coverage
for the lock-free/wait-free primitives, STM, scheduler, and consensus code).
Tests that drive the runtime from the VM/bytecode layer, do real native
`dlopen`, or exercise crypto/compress implementations that live outside this
package stay in the monorepo. Some concurrency modules (gpu, io-uring, …)
have no in-tree consumers yet — see the split design's orphan analysis.

## Usage

```lisp
(asdf:load-system :cl-cc-runtime)
```

## Development

```bash
nix develop
nix flake check        # compile check + cl-weave test suite
```

Local iteration without Nix: clone `cl-weave`, `cl-log-kit`, `cl-process-kit`,
`cl-boundary-kit`, and `cl-json-kit` from the nerima-lisp org anywhere on
disk, export `CL_CC_RUNTIME_<NAME>_ROOT` for each (see
`scripts/run-tests.lisp`), then run:

```bash
sbcl --script scripts/run-compile-check.lisp
sbcl --script scripts/run-tests.lisp
sbcl --script scripts/run-coverage.lisp   # sb-cover report under coverage/
```

## License

MIT — see [LICENSE](LICENSE).
