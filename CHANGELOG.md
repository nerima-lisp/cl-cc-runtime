# Changelog

## 0.1.2 - Unreleased

### Fixed

- Keep `COMMON-LISP` as the canonical name for the runtime's Common Lisp
  package, with `CL` as its nickname.
- When `rt-make-package` creates a runtime package before its matching host
  package exists, let `rt-intern` resolve it when it appears. Use the host
  package's symbol for names the runtime already cached and preserve symbols
  imported from other packages.
- Use one timeout budget across notifications while `rt-condition-wait-until`
  waits. On timeout, return `NIL` without another predicate call.
- Return `nil` from `rt-actor-send` when timed mailbox-lock acquisition fails,
  without enqueueing the message.

### Removed

- Remove the runtime's conflict-free replicated data type (CRDT) and Raft
  consensus APIs and tests. These distributed-state protocols are outside the
  runtime library's feature set.

### Documentation

- Describe timeout return values, mailbox limits, host I/O limitations, and
  the distinction between host conditions and compiled-target handlers.
- Limit mutation and sanitizer claims to their implemented scope; do not
  report an unmeasured coverage percentage.

### Verification scope

[Package-registry tests](t/runtime-packages-test.lisp) cover canonical names,
nicknames, and late host-package creation. [Synchronization tests](t/sync-test.lisp)
and [actor tests](t/actor-test.lisp) cover timeout budgets and failed mailbox-lock
acquisition. Passing these tests does not establish whole-compiler self-hosting,
native execution, or untested-platform behavior.
