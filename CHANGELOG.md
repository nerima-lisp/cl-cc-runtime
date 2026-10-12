# Changelog

## 0.1.2 - Unreleased

### Fixed

- Preserve `COMMON-LISP` as the canonical package name and `CL` as its nickname
  in the runtime package registry.
- Resolve host packages created after a runtime descriptor, promote cached
  uninterned symbols into that host package, and preserve imported symbols.
- Use one timeout budget across `rt-condition-wait-until` notifications and
  stop without reevaluating its predicate after a timed-out wait releases the
  mutex.
- Return `nil` from `rt-actor-send` when timed mailbox-lock acquisition fails,
  without enqueueing the message.

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
