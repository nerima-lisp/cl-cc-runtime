# Getting Started

cl-cc-runtime is distributed as a Nix flake and as an ASDF system. It requires
SBCL; it uses `sb-thread`, `sb-alien` and `sb-ext` throughout and does not
attempt to be portable across implementations.

## Add the flake input

In your `flake.nix`:

```nix
inputs.cl-cc-runtime = {
  url = "github:nerima-lisp/cl-cc-runtime/v0.1.0";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Pin a release tag. Inside this org a bare `github:nerima-lisp/cl-cc-runtime`
follows the default branch, so a push to main would change your build without
anything in your repository changing.

Add the source tree to `CL_SOURCE_REGISTRY` for whatever runs SBCL:

```nix
CL_SOURCE_REGISTRY = "${cl-cc-runtime}//:${self}//";
```

Or take the built system as a Lisp library:

```nix
pkgs.sbcl.buildASDFSystem {
  pname = "my-system";
  version = "0.1.0";
  src = self;
  systems = [ "my-system" ];
  lispLibs = [ cl-cc-runtime.packages.${system}.default ];
}
```

## Add the ASDF dependency

```lisp
(defsystem "my-system"
  :depends-on ("cl-cc-runtime")
  ...)
```

cl-cc-runtime itself depends on three sibling systems: `cl-log-kit`,
`cl-process-kit` and `cl-json-kit`. `cl-process-kit` in turn depends on
`cl-boundary-kit`, so all four have to be on the source registry even though
only three appear in this system's `:depends-on`. The flake input above wires
that up; a hand-rolled checkout has to do it explicitly.

The `:version` in `cl-cc-runtime.asd` is the single source of truth. `flake.nix`
reads it, and the release workflow refuses to publish a tag that disagrees with
it, so `v0.1.0` and `:version "0.1.0"` cannot drift apart.

## Confirm it loads

```lisp
(asdf:load-system "cl-cc-runtime")
(cl-cc/runtime:rt-gc-stats (cl-cc/runtime:make-rt-heap :young-size 64 :old-size 64))
;; => (:MINOR-GC-COUNT 0 :MAJOR-GC-COUNT 0 ...)
```

There is one package, `cl-cc/runtime`, with no nicknames. Nothing is exported
under a second name, so either qualify every call or `:use` the package in
your own `defpackage`.

## One task end to end

The rest of this page allocates two objects on a managed heap, keeps one of them
reachable, collects, and shows that the survivor moved while the garbage was
reclaimed. That is the central loop the rest of the GC API is built around.

Set up a package that uses the runtime, so the examples read without a prefix:

```lisp
(defpackage :runtime-demo
  (:use :cl :cl-cc/runtime))
(in-package :runtime-demo)
```

### Create a heap

`make-rt-heap` takes sizes in *words*, not bytes. The young generation is split
evenly into two semi-spaces, so `:young-size 64` gives two 32-word spaces.

```lisp
(defparameter *heap* (make-rt-heap :young-size 64 :old-size 64))
```

### Allocate and write a header

`rt-gc-alloc` returns a word address, not an object. It does not write the
object header; the caller does, immediately afterwards. That split exists
because the compiler emits the header write inline with the shape id it already
knows.

```lisp
(defparameter *addr* (rt-gc-alloc *heap* +rt-tag-cons+ 3))

(rt-heap-set-header *heap* *addr* (make-rt-header 3 +rt-tag-cons+ :gc-bits 0))
(rt-heap-set *heap* (+ *addr* 1) 111)
```

### Register a root

The collector does not scan the Lisp control stack. Anything that must survive
has to be reachable from a registered root. A root is a cons cell whose `cdr`
holds the address, so that the collector can update it in place when the object
moves.

```lisp
(defparameter *root* (cons nil *addr*))
(rt-gc-add-root *heap* *root*)
```

### Create some garbage and collect

```lisp
(rt-gc-alloc *heap* +rt-tag-cons+ 3)   ; nothing points at this

(rt-gc-minor-collect *heap*)
```

### Read the result

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

### The whole thing

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

[Core Concepts](guide/core-concepts.md) explains why addresses rather than
objects, what the tag constants mean, and how the value codec and the scheduler
fit alongside the heap.
