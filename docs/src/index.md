# cl-cc-runtime

cl-cc-runtime is the target runtime that the
[cl-cc](https://github.com/nerima-lisp/cl-cc) compiler emits code against. It
is a library of runtime services -- a generational garbage collector, a managed
heap, a NaN-boxed value representation, register frames, and a large set of
concurrency primitives -- exported from a single package, `cl-cc/runtime`. It
targets SBCL only.

```lisp
(let* ((heap (cl-cc/runtime:make-rt-heap :young-size 64 :old-size 64))
       (addr (cl-cc/runtime:rt-gc-alloc heap cl-cc/runtime:+rt-tag-cons+ 3)))
  (cl-cc/runtime:rt-gc-minor-collect heap)
  (getf (cl-cc/runtime:rt-gc-stats heap) :minor-gc-count))
;; => 1
```

## Where to go next

- [Getting Started](getting-started.md) adds the flake input and the
  `:depends-on` entry, confirms the system loads, then walks one task end to
  end: allocating on the managed heap, registering a root, and collecting.
- [Core Concepts](guide/core-concepts.md) explains the four ideas the rest of the API
  is built on -- word-addressed heaps, NaN boxing, roots, and cooperative
  scheduling.
- [API Reference](reference/api.md) lists the exported entry points by
  subsystem.
- [Conditions](reference/conditions.md) is the catalogue of condition types this library
  signals.
- [Architecture](reference/architecture.md) describes how `src/` is divided and why.
- [Production Readiness](project/production-readiness.md) is a written audit against
  concrete criteria: testing depth, timeout discipline, error handling,
  observability, and what is honestly still incomplete.
- [Development](project/development.md) has the build, test, coverage and formatting
  commands.

## Scope

This library is deliberately not a general-purpose concurrency toolkit for
application code. Its API is shaped by what a compiler back end needs to emit:
word addresses rather than objects, explicit root registration rather than
conservative stack scanning, and primitives that a code generator can call
without a runtime type dispatch.

If you want structured logging, process execution or JSON for ordinary
application code, use [cl-log-kit](https://github.com/nerima-lisp/cl-log-kit),
[cl-process-kit](https://github.com/nerima-lisp/cl-process-kit) and
[cl-json-kit](https://github.com/nerima-lisp/cl-json-kit) directly. This
library depends on all three rather than reimplementing them.

## Project

Source, issues and releases live at
<https://github.com/nerima-lisp/cl-cc-runtime>. Contribution guidelines, the
code of conduct, the security policy and support channels are org-wide and
live in [nerima-lisp/.github](https://github.com/nerima-lisp/.github).
