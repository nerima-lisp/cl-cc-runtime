{
  description = "cl-cc-runtime: runtime library (GC, heap, values, concurrency) for the cl-cc Common Lisp compiler";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Test-only: cl-weave is the test framework. Pulled as a plain source tree
    # and handed to the test runner via CL_CC_RUNTIME_CL_WEAVE_ROOT.
    cl-weave = {
      url = "github:nerima-lisp/cl-weave";
      flake = false;
    };
    # Runtime dependencies: cl-cc-runtime builds directly on these sibling
    # nerima-lisp libraries instead of reimplementing structured logging or
    # timeout-guarded process execution itself. Pulled as plain source trees,
    # same as cl-weave, and handed to the build/test scripts via
    # CL_CC_RUNTIME_<NAME>_ROOT. cl-boundary-kit is cl-process-kit's own
    # dependency (its injectable clock/sleeper boundaries), not something
    # cl-cc-runtime uses directly, but it must still be on the source
    # registry for ASDF to resolve cl-process-kit's :depends-on.
    cl-log-kit = {
      url = "github:nerima-lisp/cl-log-kit";
      flake = false;
    };
    cl-process-kit = {
      url = "github:nerima-lisp/cl-process-kit";
      flake = false;
    };
    cl-boundary-kit = {
      url = "github:nerima-lisp/cl-boundary-kit";
      flake = false;
    };
    cl-json-kit = {
      url = "github:nerima-lisp/cl-json-kit";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      cl-weave,
      cl-log-kit,
      cl-process-kit,
      cl-boundary-kit,
      cl-json-kit,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems =
        function: nixpkgs.lib.genAttrs systems (system: function (import nixpkgs { inherit system; }));
      runtimeDepEnv = ''
        export CL_CC_RUNTIME_CL_LOG_KIT_ROOT="${toString cl-log-kit}"
        export CL_CC_RUNTIME_CL_PROCESS_KIT_ROOT="${toString cl-process-kit}"
        export CL_CC_RUNTIME_CL_BOUNDARY_KIT_ROOT="${toString cl-boundary-kit}"
        export CL_CC_RUNTIME_CL_JSON_KIT_ROOT="${toString cl-json-kit}"
      '';
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.sbcl ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);

      packages = forAllSystems (pkgs: {
        default = pkgs.stdenvNoCC.mkDerivation {
          pname = "cl-cc-runtime";
          version = "0.1.0";
          src = self;
          nativeBuildInputs = [ pkgs.sbcl ];
          buildPhase = ''
            export HOME="$TMPDIR/home"
            mkdir -p "$HOME"
            ${runtimeDepEnv}
            sbcl --noinform --non-interactive --script scripts/run-compile-check.lisp
          '';
          installPhase = ''
            mkdir -p "$out/share/common-lisp/source/cl-cc-runtime"
            cp -R . "$out/share/common-lisp/source/cl-cc-runtime"
          '';
          meta = {
            description = "cl-cc runtime: GC, heap, values, FFI, concurrency";
            homepage = "https://github.com/nerima-lisp/cl-cc-runtime";
            license = pkgs.lib.licenses.mit;
            platforms = pkgs.lib.platforms.unix;
          };
        };
      });

      checks = forAllSystems (pkgs: {
        compile = self.packages.${pkgs.stdenv.hostPlatform.system}.default;

        test = pkgs.stdenvNoCC.mkDerivation {
          name = "cl-cc-runtime-test";
          src = self;
          nativeBuildInputs = [ pkgs.sbcl ];
          buildPhase = ''
            export HOME="$TMPDIR/home"
            mkdir -p "$HOME"
            export CL_CC_RUNTIME_CL_WEAVE_ROOT="${toString cl-weave}"
            ${runtimeDepEnv}
            sbcl --noinform --non-interactive --script scripts/run-tests.lisp
          '';
          installPhase = "touch $out";
        };
      });
    };
}
