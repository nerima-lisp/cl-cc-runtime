{
  description = "cl-cc runtime library: rt-* primitives, GC, heap, frame, value codec, and concurrency";

  inputs = {
    # nixos-unstable, not nixpkgs-unstable: it advances only after the NixOS
    # release tests pass, so it is less likely to land a broken build.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Every sibling is pinned to a release tag. A bare
    # `github:nerima-lisp/cl-log-kit` follows that repository's default branch,
    # so an upstream push to main would break this repository's CI without
    # anything changing here.
    #
    # `inputs.nixpkgs.follows` is on every input: without it each one locks its
    # own nixpkgs, which inflates flake.lock and rebuilds SBCL once per copy.
    #
    # cl-cc-runtime sits at depth 3, the deepest point in the org, so the
    # sibling flakes below also depend on each other. Each shared input is
    # redirected at this level too. Without those extra `follows` the lock
    # carries 75 nodes -- four different cl-weave revisions, four paredit-cli
    # revisions and eleven copies of rust-overlay -- for a library that has
    # three dependencies. The rule is the same one nixpkgs.follows encodes:
    # one version of a thing per lock file.
    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    cl-log-kit = {
      url = "github:nerima-lisp/cl-log-kit/v1.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-json-kit.follows = "cl-json-kit";
      inputs.cl-process-kit.follows = "cl-process-kit";
      inputs.cl-weave.follows = "cl-weave";
      inputs.paredit-cli.follows = "cl-weave/paredit-cli";
    };
    cl-json-kit = {
      url = "github:nerima-lisp/cl-json-kit/v1.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-weave.follows = "cl-weave";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };
    # Not a direct dependency of cl-cc-runtime: cl-process-kit's own .asd
    # declares it, so ASDF cannot resolve "cl-process-kit" unless
    # cl-boundary-kit is on the source registry too. v0.6.0 is what
    # cl-process-kit v1.0.0 itself pins, so the two agree.
    cl-boundary-kit = {
      url = "github:nerima-lisp/cl-boundary-kit/v0.6.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-json-kit.follows = "cl-json-kit";
      inputs.cl-log-kit.follows = "cl-log-kit";
      inputs.cl-process-kit.follows = "cl-process-kit";
      inputs.cl-weave.follows = "cl-weave";
    };
    cl-process-kit = {
      url = "github:nerima-lisp/cl-process-kit/v1.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-boundary-kit.follows = "cl-boundary-kit";
      inputs.cl-log-kit.follows = "cl-log-kit";
      inputs.cl-weave.follows = "cl-weave";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      cl-weave,
      cl-log-kit,
      cl-json-kit,
      cl-boundary-kit,
      cl-process-kit,
      treefmt-nix,
      ...
    }:
    let
      # Only the two platforms that are actually verified are declared.
      # x86_64-linux is what the ubuntu CI runner builds; aarch64-darwin is the
      # development machine, so every local `nix flake check` exercises it.
      # aarch64-linux and x86_64-darwin were declared here before and nothing
      # ever built them, which is exactly the gap this list exists to close.
      # See ADR-0078.
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      # One variable instead of the five CL_CC_RUNTIME_<NAME>_ROOT variables
      # this flake used to export: run-tests.lisp registers the checkout and
      # inherits the rest from here, so a new dependency is one entry, not two.
      sourceRegistry = "${cl-boundary-kit}//:${cl-json-kit}//:${cl-log-kit}//:${cl-process-kit}//:${cl-weave}//:${self}//";

      # Reads the first `:version` form out of an ASDF system definition. Nix
      # regexes are anchored to the whole string and `.` never spans newlines,
      # so the file is split into lines and matched line by line rather than
      # with one multi-line match. The anchoring is also what stops a
      # `:depends-on ((:version "asdf" "3.3.1"))` line from being read as the
      # system's own version: such a line does not match end to end.
      asdVersion =
        asd:
        let
          lines = nixpkgs.lib.splitString "\n" (builtins.readFile asd);
          versionLine = builtins.head (
            builtins.filter (line: builtins.match "[[:space:]]*:version \"[^\"]*\"" line != null) lines
          );
        in
        builtins.head (builtins.match "[[:space:]]*:version \"([^\"]*)\"" versionLine);

      # Single source of truth for the version: the `:version` form in
      # cl-cc-runtime.asd. A release edits that one line and the packages, the
      # docs site and release.yml's tag check all follow. This flake used to
      # hardcode "0.1.0" as well, which is how cl-cc ended up carrying three
      # version numbers that disagreed with each other.
      version = asdVersion ./cl-cc-runtime.asd;

      # Sibling versions are read out of each pinned source's own .asd for the
      # same reason: a copy of the number in this file goes stale silently.
      clBoundaryKitVersion = asdVersion "${cl-boundary-kit}/cl-boundary-kit.asd";
      clJsonKitVersion = asdVersion "${cl-json-kit}/cl-json-kit.asd";
      clLogKitVersion = asdVersion "${cl-log-kit}/cl-log-kit.asd";
      clProcessKitVersion = asdVersion "${cl-process-kit}/cl-process-kit.asd";

      # treefmt drives `nix fmt` and the `checks.<system>.formatting` gate.
      # Scope is Nix only: nixfmt is a low-diff, zero-footgun formatter,
      # whereas a YAML formatter mangles the GitHub Actions `on:` key and
      # reformatting Markdown would churn the whole docs tree.
      treefmtEval = forAllSystems (
        system:
        treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${system} {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
        }
      );

      # The site is built from the repository root rather than from docs/,
      # because docs/src/changelog.md pulls in the root CHANGELOG.md through a
      # pymdownx.snippets include whose base_path is ".".
      mkDocs =
        pkgs:
        pkgs.stdenvNoCC.mkDerivation {
          pname = "cl-cc-runtime-docs";
          inherit version;
          src = pkgs.lib.fileset.toSource {
            root = ./.;
            fileset = pkgs.lib.fileset.unions [
              ./docs/mkdocs.yml
              ./docs/src
              ./CHANGELOG.md
            ];
          };
          nativeBuildInputs = [ pkgs.python3Packages.mkdocs-material ];
          # Builds fully offline: Material for MkDocs bundles its own assets,
          # so no network access is needed inside the Nix sandbox. --strict
          # promotes broken links and unlisted pages to build failures.
          buildPhase = ''
            runHook preBuild
            mkdocs build --strict --config-file docs/mkdocs.yml --site-dir "$out"
            runHook postBuild
          '';
          dontInstall = true;
          meta = {
            description = "Rendered MkDocs (Material) documentation for cl-cc-runtime";
            homepage = "https://github.com/nerima-lisp/cl-cc-runtime";
            license = pkgs.lib.licenses.mit;
          };
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          # The siblings are rebuilt here from their pinned sources rather than
          # taken from each repository's own `packages.default`: that would tie
          # this build to their flake outputs instead of to their .asd files,
          # and nothing in nixpkgs packages them.
          clLogKit = pkgs.sbcl.buildASDFSystem {
            pname = "cl-log-kit";
            version = clLogKitVersion;
            src = cl-log-kit;
            systems = [ "cl-log-kit" ];
          };
          clJsonKit = pkgs.sbcl.buildASDFSystem {
            pname = "cl-json-kit";
            version = clJsonKitVersion;
            src = cl-json-kit;
            systems = [ "cl-json-kit" ];
          };
          clBoundaryKit = pkgs.sbcl.buildASDFSystem {
            pname = "cl-boundary-kit";
            version = clBoundaryKitVersion;
            src = cl-boundary-kit;
            systems = [ "cl-boundary-kit" ];
            lispLibs = [ clLogKit ];
          };
          clProcessKit = pkgs.sbcl.buildASDFSystem {
            pname = "cl-process-kit";
            version = clProcessKitVersion;
            src = cl-process-kit;
            systems = [ "cl-process-kit" ];
            lispLibs = [
              clBoundaryKit
              clLogKit
            ];
          };
        in
        rec {
          cl-cc-runtime = pkgs.sbcl.buildASDFSystem {
            pname = "cl-cc-runtime";
            inherit version;
            src = self;
            systems = [ "cl-cc-runtime" ];
            lispLibs = [
              clJsonKit
              clLogKit
              clProcessKit
            ];
          };
          default = cl-cc-runtime;

          docs = mkDocs pkgs;
        }
      );

      # `nix fmt` entry point.
      formatter = forAllSystems (system: treefmtEval.${system}.config.build.wrapper);

      # Granularity lives here, NOT in extra GitHub Actions jobs: `nix flake
      # check` evaluates each attribute as its own derivation, in parallel,
      # with build caching. Add a check here rather than a job in ci.yml.
      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          # Compiles the whole system on the way to running the suite, so this
          # subsumes the compile-only derivation that used to be
          # `packages.default`. The timeout is 600s rather than the 120s the
          # org template uses: the suite starts real threads for the lock-free,
          # STM, scheduler and consensus tests, so it is not a pure-library
          # suite and a 120s budget would make CI flaky under load.
          default =
            pkgs.runCommand "cl-cc-runtime-tests"
              {
                nativeBuildInputs = [
                  pkgs.sbcl
                  pkgs.coreutils
                ];
                CL_SOURCE_REGISTRY = sourceRegistry;
              }
              ''
                export HOME="$TMPDIR/home"
                mkdir -p "$HOME" "$out"
                timeout 600 sbcl --script ${self}/run-tests.lisp
                touch "$out/passed"
              '';

          # Fails `nix flake check` when any tracked Nix file is unformatted,
          # turning the formatter into an enforced gate rather than a habit.
          formatting = treefmtEval.${system}.config.build.check self;

          # packages.docs runs `mkdocs build --strict`, so a broken link or a
          # page missing from the nav fails here. Without this check the site
          # is only ever built by docs.yml, which runs after a merge to main --
          # so a break would surface as a failed deploy rather than as a failed
          # pull request.
          docs = self.packages.${system}.docs;
        }
      );

      apps = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          test = pkgs.writeShellApplication {
            name = "cl-cc-runtime-test";
            runtimeInputs = [
              pkgs.sbcl
              pkgs.coreutils
            ];
            text = ''
              export CL_SOURCE_REGISTRY="${sourceRegistry}"
              exec timeout 600 sbcl --script ${self}/run-tests.lisp
            '';
          };
        in
        {
          default = {
            type = "app";
            program = "${test}/bin/cl-cc-runtime-test";
          };
          test = {
            type = "app";
            program = "${test}/bin/cl-cc-runtime-test";
          };
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [ pkgs.sbcl ];
            CL_SOURCE_REGISTRY = sourceRegistry;
          };
        }
      );
    };
}
