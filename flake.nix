{
  description = "cl-cc runtime library: rt-* primitives, GC, heap, frame, value codec, and concurrency";

  inputs = {
    # nixos-unstable, not nixpkgs-unstable: it advances only after the NixOS
    # release tests pass, so it is less likely to land a broken build.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # The org's shared Nix/ASDF-derivation library. One `mkPackageFlake` call
    # below generates this repository's whole packages/checks/apps/devShells/
    # formatter/overlays output table, so it cannot drift from the other 20
    # repositories the way the ~320-line hand-rolled version of this file
    # used to.
    cl-nix-forge = {
      url = "github:nerima-lisp/cl-nix-forge/v0.4.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Every sibling is pinned to a release tag. A bare
    # `github:nerima-lisp/cl-log-kit` follows that repository's default branch,
    # so an upstream push to main would break this repository's CI without
    # anything changing here.
    #
    # `inputs.nixpkgs.follows` is on every input: without it each one locks its
    # own nixpkgs, which inflates flake.lock and rebuilds SBCL once per copy.
    # `inputs.cl-nix-forge.follows` is on every sibling that itself takes a
    # cl-nix-forge input: without it, two different cl-nix-forge revisions'
    # `ancestry` shapes can disagree and the dependency walk in
    # `lib/core/dedup.nix` fails with "attribute 'ancestry' missing" trying to
    # merge a subtree built by the other one.
    #
    # cl-boundary-kit is NOT listed here even though cl-process-kit's own
    # `.asd` depends on it: cl-process-kit's own package output already
    # carries its build of cl-boundary-kit in its dependency closure
    # (`ancestry`), and `lispDerivation`'s registry walk is transitive, so
    # listing cl-process-kit as a `lispDependencies` entry below is
    # sufficient -- see cl-process-kit's own flake.nix, where cl-boundary-kit
    # is built once and threaded through, never re-derived by a downstream
    # consumer.
    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.1.4";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-nix-forge.follows = "cl-nix-forge";
    };
    cl-log-kit = {
      url = "github:nerima-lisp/cl-log-kit/v2.0.1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-nix-forge.follows = "cl-nix-forge";
    };
    cl-json-kit = {
      url = "github:nerima-lisp/cl-json-kit/v1.0.2";
      inputs.nixpkgs.follows = "nixpkgs";
      # No `cl-nix-forge.follows`: this tag predates cl-json-kit's own
      # migration to mkPackageFlake, so its flake.nix declares no
      # cl-nix-forge input of its own to redirect.
    };
    cl-process-kit = {
      url = "github:nerima-lisp/cl-process-kit/v3.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-nix-forge.follows = "cl-nix-forge";
    };

    # The 2026-08-01 uiop->cl-host-kit org migration's real (non-test)
    # dependency. Already on mkPackageFlake upstream, so this follows the
    # same `packages.${system}` shape as cl-log-kit/cl-process-kit above
    # rather than cl-json-kit's fromDerivation leaf-wrapping.
    cl-host-kit = {
      url = "github:nerima-lisp/cl-host-kit/v0.2.5";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-nix-forge.follows = "cl-nix-forge";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      cl-nix-forge,
      cl-weave,
      cl-log-kit,
      cl-json-kit,
      cl-process-kit,
      cl-host-kit,
      treefmt-nix,
    }:
    let
      # x86_64-linux is what CI gates; aarch64-darwin is the development
      # machine. Every per-system output -- packages, checks, apps AND devShells
      # -- comes from this one list, so leaving aarch64-darwin out takes `nix
      # build` and `nix develop` off the development machine as well. That trade
      # was made on 2026-08-01 and reverted on 2026-08-02; aarch64-darwin carries
      # no CI gate, which PACKAGE_STANDARD.md's "systems" section accepts
      # explicitly. aarch64-linux and x86_64-darwin are nobody's verification and
      # are not declared.
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
    in
    # `mkPackageFlake` spans systems -- it obtains a `pkgs` and its own
    # cl-nix-forge instance per entry in `systems` -- so the per-system `lib`
    # this function is taken from contributes nothing but the function itself.
    cl-nix-forge.lib.${builtins.head systems}.mkPackageFlake {
      inherit self systems nixpkgs;

      pname = "cl-cc-runtime";

      # Single source of truth for the version: the `:version` form in
      # cl-cc-runtime.asd. A release edits that one line and the packages, the
      # docs site and release.yml's tag check all follow. There is
      # deliberately no `version` argument to pass.
      asd = ./cl-cc-runtime.asd;

      # Spelled out rather than left to the documented default of `self`,
      # because that default does not evaluate: a flake's `self` is an
      # attrset carrying an `outPath`, and `lib.fileset` refuses a
      # string-like value for its root. `./.` is the same directory as a
      # path literal.
      root = ./.;

      meta = {
        description = "cl-cc runtime library: rt-* primitives, GC, heap, frame, value codec, and concurrency";
        homepage = "https://github.com/nerima-lisp/cl-cc-runtime";
        license = nixpkgs.lib.licenses.mit;
        platforms = nixpkgs.lib.platforms.unix;
      };

      # Real runtime dependencies (see cl-cc-runtime.asd's `:depends-on`):
      # each sibling's own flake builds its ASDF system, so this is an
      # ordinary `lispDependencies` entry rather than a hand-rolled registry
      # string.
      #
      # cl-log-kit v2.0.0 and cl-process-kit v2.0.0 already build themselves
      # with cl-nix-forge (`mkPackageFlake` and `lispDerivation` respectively),
      # so their package outputs carry cl-nix-forge's own dependency-ancestry
      # metadata as-is. cl-json-kit v1.0.1 still predates its own migration,
      # so it needs `fromDerivation` leaf-wrapping until a `mkPackageFlake`
      # release is tagged upstream -- without it, `dedup.nix` cannot merge its
      # ancestry-less output into this package's own dependency tree; drop
      # the wrapping once a migrated cl-json-kit release is tagged.
      #
      # cl-process-kit v2.0.0 itself still pins cl-boundary-kit at v1.0.0 and
      # cl-log-kit at v1.0.0 as ITS OWN inputs (see its flake.nix) -- that
      # choice is baked into its released package output and this flake
      # cannot override it. That means the resolved CL_SOURCE_REGISTRY below
      # carries two different cl-log-kit source trees: this flake's own
      # direct v2.0.0 pin, and the v1.0.0 copy embedded in cl-process-kit's
      # closure. `lib/core/dedup.nix` only collapses dependencies that share
      # a source-tree identity, so the two do NOT merge, and ASDF resolves
      # the duplicate system name by registry order -- which this preset
      # builds from Nix attrset iteration and is therefore not something a
      # flake author controls. This is safe here specifically because
      # cl-log-kit v2.0.0's changelog states no exported symbol from v1.0.0
      # was removed, cl-cc-runtime's own `:import-from` list (verified
      # against v2.0.0's `package.lisp`) only names symbols present in both,
      # and cl-cc-runtime does not call `rotating-file-handler`, the one
      # symbol whose behaviour changed. Whichever copy ASDF picks, the build
      # and test suite are unaffected. Revisit if cl-process-kit ever bumps
      # its own cl-log-kit pin, at which point this whole paragraph -- and
      # the duplicate -- disappears.
      lispDependencies = ctx: [
        cl-log-kit.packages.${ctx.system}.cl-log-kit
        cl-process-kit.packages.${ctx.system}.cl-process-kit
        (ctx.cl.fromDerivation { drv = cl-json-kit.packages.${ctx.system}.cl-json-kit; })
        cl-host-kit.packages.${ctx.system}.cl-host-kit
      ];

      # cl-weave is a dependency of cl-cc-runtime/test and of nothing else
      # (see cl-cc-runtime.asd), so it is a CHECK dependency: it must not
      # enter the library's own closure or the overlay's `pkgs.cl-cc-runtime`.
      # cl-weave v1.1.0 already builds itself with `mkPackageFlake`, so its
      # package output carries cl-nix-forge's ancestry metadata as-is and
      # needs no `fromDerivation` wrapping.
      lispCheckDependencies = ctx: [
        cl-weave.packages.${ctx.system}.cl-weave
      ];

      # Drives BOTH `checks.default` and `apps.test`, from this one number, so
      # the command a contributor runs by hand and the gate CI runs cannot
      # drift apart. 600s, not the preset's own 600s default left implicit:
      # spelled out because it is a deliberate choice, not an accident of the
      # default -- this suite starts real threads for the lock-free, STM,
      # scheduler and consensus tests, so it is not a pure-library suite and a
      # shorter budget would make CI flaky under load.
      timeoutSeconds = 600;

      # The site is built from the repository root rather than from docs/, so
      # the config path is the same `docs/mkdocs.yml` a contributor types by
      # hand.
      docs = {
        root = ./.;
        fileset = nixpkgs.lib.fileset.unions [
          ./docs/mkdocs.yml
          ./docs/src
        ];
        mkdocsYmlName = "docs/mkdocs.yml";
      };

      # ONE treefmt evaluation drives both `nix fmt` and the
      # `checks.formatting` gate, so the formatter and CI cannot disagree
      # about what "formatted" means. `evalModule` is passed in rather than
      # closed over so this repository picks its own treefmt-nix version.
      # Scope stays the preset's default of Nix only: nixfmt is a low-diff,
      # zero-footgun formatter, whereas a YAML formatter mangles the GitHub
      # Actions `on:` key and reformatting Markdown would churn the whole
      # docs tree.
      treefmt.evalModule = treefmt-nix.lib.evalModule;
    };
}
