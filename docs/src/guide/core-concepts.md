# Core Concepts

Four ideas account for most of the API surface. Everything else is a variation
on one of them.

## The heap is a word vector, not an object graph

`make-rt-heap` allocates one flat `simple-vector` and hands out integer indices
into it. `rt-gc-alloc` returns such an index; `rt-heap-ref` and `rt-heap-set`
read and write single words at one.

```
[0 .. semi-1]              young from-space
[semi .. 2*semi-1]         young to-space
[2*semi .. 2*semi+old-1]   old space
[.. large-obj-size]        large-object space
```

The reason for a flat vector rather than real Lisp objects is that the compiler
emits code that computes addresses. A field access in the generated code is an
integer add and a vector reference, which is what the target machine would do;
if the runtime stored real conses the generated code could not be checked
against the object layout it assumes.

The practical consequence is that an address is only valid until the next
collection. Nothing in the type system enforces that.

## Objects carry a one-word header

Each object begins with a header word packing its size, its type tag and its GC
bits. `make-rt-header` builds one, `rt-header-size`, `rt-header-type-tag` and
`rt-header-age` read the fields back.

`rt-gc-alloc` deliberately does not write the header. The allocator returns
uninitialised storage and the caller writes the header immediately after,
because the compiler already knows the shape id to embed and a second pass over
the object to fill it in would be wasted work.

Type tags come from the `+rt-tag-*+` constants: `+rt-tag-cons+`,
`+rt-tag-symbol+`, `+rt-tag-function+`, `+rt-tag-string+`, and `+tag-other+`
for everything else.

## Roots are explicit, and the collector rewrites them

The collector is a moving, generational collector: a minor collection copies
live objects from from-space to to-space, and objects that survive enough
collections are promoted to old space.

Because objects move, the collector must be able to find and update every
reference to them. It does not scan the control stack, so it can only update
references it was told about. `rt-gc-add-root` takes a cons cell and treats its
`cdr` as a mutable slot:

```lisp
(let ((root (cons nil addr)))
  (rt-gc-add-root heap root)
  (rt-gc-minor-collect heap)
  (cdr root))          ; the new address
```

`rt-gc-remove-root` takes the same cell back off the root set. A root left
registered keeps its object alive forever, which is the usual cause of a heap
that never shrinks.

Writes from old space into young space have to be recorded, or a minor
collection would miss them: `rt-gc-write-barrier` marks the corresponding card
in the card table, and the minor collector scans dirty cards as additional
roots.

## Values are NaN-boxed 64-bit words

Separately from the heap, `value.lisp` and its split-out files
(`value-tags.lisp` for the tag/mask constants, `value-codec.lisp` for the
encoders and decoders) define a tagged 64-bit representation in which a
double-precision float is stored as itself and everything else is stored
inside the payload of a quiet NaN.

```lisp
(encode-fixnum 42)        ; => 344064
(decode-fixnum 344064)    ; => 42
(val-fixnum-p 344064)     ; => T
(val-double-p 344064)     ; => NIL
```

The encoders are `encode-fixnum`, `encode-double`, `encode-pointer`,
`encode-char` and `encode-bool`, each with a matching decoder, and the
predicates are the `val-*-p` family. `+val-nil+`, `+val-t+` and
`+val-unbound+` are the three singleton values.

This is what lets a compiled program pass an unboxed float and a tagged pointer
through the same register: floats need no allocation at all, and the type test
on everything else is a mask and a compare.

## Concurrency is cooperative by default

The scheduler in `scheduler.lisp` runs green threads on one native thread.
`rt-spawn` queues a thunk, `rt-scheduler-run` runs the queue to completion, and
`rt-yield` puts the current green thread back on the queue.

```lisp
(rt-scheduler-init)
(let ((ch (rt-make-channel :capacity 1)))
  (rt-spawn (lambda () (rt-channel-send ch 7)))
  (rt-scheduler-run)
  (rt-channel-recv ch))
;; => 7
```

Around that core sit the other concurrency models, all reachable from the same
package: CSP channels, actors, futures, fibers, algebraic effects, software
transactional memory, and lock-free stacks, queues and hash maps with four
reclamation schemes (epoch-based, hazard pointers, RCU and QSBR).

They are separate because they make different trade-offs, not because one
supersedes another. A compiler back end picks the one that matches the source
language's concurrency model; see [API Reference](../reference/api.md) for the
entry points of each.

Native threads are available too, via the `sb-thread` facades in
`portable.lisp` and `scheduler-native-thread.lisp`. The lock-free structures
and the reclamation schemes are the parts that assume real parallelism; the
green-thread scheduler is not thread-safe across native threads by itself.
