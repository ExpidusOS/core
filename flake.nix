{
  description = "ExpidusOS Core";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    toolchain.url = "git+https://gitlab.midstall.com/ExpidusOS/toolchain.git";
    zon2nix.url = "github:MidstallSoftware/zon2nix/expidus";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, toolchain, zon2nix, flake-utils }@inputs:
    let
      zon2nixOverlay = final: prev: {
        zon2nix = prev.stdenv.mkDerivation {
          pname = "zon2nix";
          version = "0.1.2";

          src = zon2nix;

          nativeBuildInputs = [
            prev.zig
          ];

          buildInputs = [
            prev.stdenv.cc.cc.lib
            prev.stdenv.cc.cc.libc_dev.out
          ];

          dontConfigure = true;
          dontInstall = true;

          buildPhase = ''
            mkdir -p .cache
            zig build install --cache-dir $(pwd)/zig-cache --global-cache-dir $(pwd)/.cache \
              -Dnix=${prev.lib.getExe prev.nix} \
              -Dcpu=baseline \
              -Doptimize=ReleaseSafe \
              --prefix $out
          '';
        };
      };
    in flake-utils.lib.eachSystem flake-utils.lib.allSystems (
      system:
        let
          pkgs = (import nixpkgs {inherit system;}).appendOverlays [
            toolchain.overlays.patches
            toolchain.overlays.zig
            toolchain.overlays.default
            zon2nixOverlay
          ];
        in {
          packages.default = pkgs.stdenvNoCC.mkDerivation {
            pname = "expidus-core";
            version = self.shortRev or "dirty";

            src = pkgs.lib.cleanSource self;

            outputs = [ "out" "dev" ];

            nativeBuildInputs = with pkgs; [
              expidus.toolchain
            ];

            dontConfigure = true;
            dontInstall = true;

            buildPhase = ''
              export ZIG_GLOBAL_CACHE_DIR=$(pwd)/.cache
              mkdir -p .cache
              ln -s ${pkgs.callPackage ./deps.nix { }} .cache/p

              zig build install --cache-dir $(pwd)/zig-cache --global-cache-dir $(pwd)/.cache \
                -Dbuild-hash=${self.shortRev or "dirty"} \
                -Dcpu=baseline \
                -Doptimize=ReleaseSafe \
                --prefix $out
            '';
          };

          legacyPackages = pkgs;

          devShells.default = pkgs.mkShell {
            name = "expidus-core";

            packages = with pkgs; [
              expidus.toolchain
              pkgs.zon2nix
            ];
          };
        });
}
