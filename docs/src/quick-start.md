# Quick Start

This walks one task end to end: allocate two objects on a managed heap, keep
one of them reachable, collect, and see that the survivor moved while the
garbage was reclaimed. That is the central loop the rest of the GC API is built
around.

Set up a package that uses the runtime, so the examples read without a prefix:

```lisp
(asdf:load-system "cl-cc-runtime")

(defpackage :runtime-demo
  (:use :cl :cl-cc/runtime))
(in-package :runtime-demo)
```

## Create a heap

`make-rt-heap` takes sizes in *words*, not bytes. The young generation is split
evenly into two semi-spaces, so `:young-size 64` gives two 32-word spaces.

```lisp
(defparameter *heap* (make-rt-heap :young-size 64 :old-size 64))
```

## Allocate and write a header

`rt-gc-alloc` returns a word address, not an object. It does not write the
object header; the caller does, immediately afterwards. That split exists
because the compiler emits the header write inline with the shape id it already
knows.

```lisp
(defparameter *addr* (rt-gc-alloc *heap* +rt-tag-cons+ 3))

(rt-heap-set-header *heap* *addr* (make-rt-header 3 +rt-tag-cons+ :gc-bits 0))
(rt-heap-set *heap* (+ *addr* 1) 111)
```

## Register a root

The collector does not scan the Lisp control stack. Anything that must survive
has to be reachable from a registered root. A root is a cons cell whose `cdr`
holds the address, so that the collector can update it in place when the object
moves.

```lisp
(defparameter *root* (cons nil *addr*))
(rt-gc-add-root *heap* *root*)
```

## Create some garbage and collect

```lisp
(rt-gc-alloc *heap* +rt-tag-cons+ 3)   ; nothing points at this

(rt-gc-minor-collect *heap*)
```

## Read the result

The survivor has moved, its payload is intact, and the unreachable object's
words were reclaimed:

```lisp
(cdr *root*)
;; => 32   (a new address in the other semi-space)

(rt-heap-ref *heap* (+ (cdr *root*) 1))
;; => 111

(getf (rt-gc-stats *heap*) :minor-gc-count)
;; => 1

(getf (rt-gc-stats *heap*) :words-collected)
;; => 29
```

Note that `*addr*` is now stale. After a collection the only valid address is
the one in the root cell. This is the single rule that most misuse of the API
comes down to.

## The whole thing

```lisp
(asdf:load-system "cl-cc-runtime")

(defpackage :runtime-demo
  (:use :cl :cl-cc/runtime))
(in-package :runtime-demo)

(let* ((heap (make-rt-heap :young-size 64 :old-size 64))
       (addr (rt-gc-alloc heap +rt-tag-cons+ 3))
       (root (cons nil addr)))
  (rt-heap-set-header heap addr (make-rt-header 3 +rt-tag-cons+ :gc-bits 0))
  (rt-heap-set heap (+ addr 1) 111)
  (rt-gc-add-root heap root)
  (rt-gc-alloc heap +rt-tag-cons+ 3)
  (rt-gc-minor-collect heap)
  (list :moved-to (cdr root)
        :value (rt-heap-ref heap (+ (cdr root) 1))
        :collected (getf (rt-gc-stats heap) :words-collected)))
;; => (:MOVED-TO 32 :VALUE 111 :COLLECTED 29)
```

## Next

[Core Concepts](core-concepts.md) explains why addresses rather than objects,
what the tag constants mean, and how the value codec and the scheduler fit
alongside the heap.
