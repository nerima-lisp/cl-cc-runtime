# Conditions

This page lists the condition types cl-cc-runtime defines and signals. They are
host Common Lisp conditions, signalled with `error`, `warn` and `signal`, and
handled with `handler-case` and `handler-bind` as usual.

They are separate from the *runtime* condition system -- `rt-signal`,
`rt-establish-handler`, `rt-restart-case` and friends -- which implements
handlers and restarts for the compiled program. This page is about the
conditions the library signals at *you*; that machinery is about the conditions
a compiled program signals at itself. See
[API Reference](api-reference.md#conditions-and-restarts) for the latter.

## Memory

### `rt-stack-overflow`

Subtype of `storage-condition`. Signalled when the runtime stack depth guard
trips. The guard exists because a compiled program's recursion is not the
host's recursion, so SBCL's own control stack exhaustion would fire at an
unrelated depth, or not at all.

### `rt-oom-condition`

Subtype of `storage-condition`. Signalled when the managed heap is exhausted
and a collection did not free enough to satisfy the allocation. Increase
`:young-size` or `:old-size` when creating the heap, or check for a root that
is never removed.

### `rt-gc-pressure-warning`

Subtype of `warning`. Signalled when heap occupancy crosses
`rt-heap-pressure-threshold-high`. It is a warning rather than an error because
the allocation still succeeded; it is the signal to shed load or grow the heap
before an `rt-oom-condition` follows.

## Concurrency

### `rt-stm-conflict`

Subtype of `error`. Signalled when a transaction commits against a
transactional variable that changed underneath it. `rt-atomically` handles this
itself and retries, so it only escapes when a transaction is driven by hand
with `rt-read-tvar` and `rt-write-tvar`.

### `rt-stm-retry`

Subtype of `condition`, not `error`. Signalled by `rt-retry` to abort the
current transaction and wait for one of its read variables to change. It is a
control-flow signal, so a `handler-case` on `error` will not catch it.

### `rt-effect-condition`

Subtype of `error`. The base type for algebraic effects raised by `rt-perform`.
`rt-with-handler` catches it; an effect performed with no handler installed
reaches the caller as this error.

## Operating system

### `rt-os-signal-condition`

Base type for OS signals delivered into Lisp. It is a plain `condition`, not an
`error`, because most signals are informational and the default action is to
continue.

### `rt-segmentation-violation`

Subtype of `storage-condition` and `rt-os-signal-condition`. `SIGSEGV`
delivered as a condition. Reaching this from Lisp code normally means an FFI
call or a raw `rt-mmap-raw` region went out of bounds.

### `rt-floating-point-exception`

Subtype of `arithmetic-error` and `rt-os-signal-condition`. `SIGFPE` delivered
as a condition.

### `rt-interrupt`

Subtype of `simple-condition` and `rt-os-signal-condition`. An asynchronous
interrupt.

### `keyboard-interrupt`

Subtype of `rt-interrupt`. `SIGINT`. It is named without the `rt-` prefix
because it is the condition a host-level driver loop is expected to catch, and
`handler-case` on it reads the same way it does elsewhere.

## Instrumentation

### `perf-counters-unsupported`

Subtype of `condition`, not `error`. Signalled by `rt-perf-read-counter` and
`rt-with-perf-counters` on a platform with no hardware performance counters.
It is not an error because instrumentation should not take a program down;
handle it and fall back to wall-clock timing.

## Handling them

```lisp
(handler-case
    (rt-gc-alloc heap +rt-tag-cons+ 1000000)
  (cl-cc/runtime:rt-oom-condition (c)
    (format t "~&heap exhausted: ~a~%" c)
    nil))
```

Not every type on this page is exported yet. `rt-oom-condition`,
`rt-gc-pressure-warning`, `rt-stm-conflict`, `rt-stm-retry`, `rt-interrupt`,
`keyboard-interrupt` and `perf-counters-unsupported` are; `rt-stack-overflow`,
`rt-effect-condition`, `rt-os-signal-condition`,
`rt-segmentation-violation` and `rt-floating-point-exception` currently need
the `cl-cc/runtime::` double-colon form. Widening the export list is tracked as
follow-up work -- a condition a caller is meant to catch by name has to be
exported to be catchable by name.
