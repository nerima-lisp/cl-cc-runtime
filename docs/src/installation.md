# Installation

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

## Confirm it loads

```lisp
(asdf:load-system "cl-cc-runtime")
(cl-cc/runtime:rt-gc-stats (cl-cc/runtime:make-rt-heap :young-size 64 :old-size 64))
;; => (:MINOR-GC-COUNT 0 :MAJOR-GC-COUNT 0 ...)
```

There is one package, `cl-cc/runtime`, with no nicknames. Nothing is exported
under a second name, so either qualify every call or `:use` the package in
your own `defpackage`.

## Versions

The `:version` in `cl-cc-runtime.asd` is the single source of truth. `flake.nix`
reads it, and the release workflow refuses to publish a tag that disagrees with
it, so `v0.1.0` and `:version "0.1.0"` cannot drift apart.
