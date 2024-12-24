{
  description = "Emerald linker";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    zig.url = "github:mitchellh/zig-overlay";
    zls.url = "github:zigtools/zls";

    # Used for shell.nix
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  } @ inputs: let
    overlays = [
      # Other overlays
      (final: prev: {
        zigpkgs = inputs.zig.packages.${prev.system};
        zlspkgs = inputs.zls.packages.${prev.system};
      })
    ];

    # Our supported systems are the same supported systems as the Zig binaries
    systems = builtins.attrNames inputs.zig.packages;
  in
    flake-utils.lib.eachSystem systems (
      system: let
        pkgs = import nixpkgs {inherit overlays system;};
      in rec {
        commonInputs = with pkgs; [
          zigpkgs."0.13.0"
        ];

        tracy-version = "0.10";
        tracy-src = pkgs.fetchFromGitHub {
          owner = "wolfpld";
          repo = "tracy";
          rev = "v${tracy-version}";
          hash = "sha256-DN1ExvQ5wcIUyhMAfiakFbZkDsx+5l8VMtYGvSdboPA=";
        };

        packages.default = packages.emerald;
        packages.emerald = pkgs.stdenv.mkDerivation {
          name = "emerald";
          version = "master";
          src = ./.;
          nativeBuildInputs = commonInputs;
          dontConfigure = true;
          dontInstall = true;
          doCheck = false; # TODO enable this
          buildPhase = ''
            mkdir -p .cache
            zig build install -Doptimize=ReleaseFast --prefix $out --cache-dir $(pwd)/.zig-cache --global-cache-dir $(pwd)/.cache 
          '';
          checkPhase = ''
            zig build test -Dhas-zig --cache-dir $(pwd)/.zig-cache --global-cache-dir $(pwd)/.cache
          '';
        };

        devShells.default = pkgs.mkShell {
          buildInputs = commonInputs ++ (with pkgs; [
            zlspkgs.default
            tracy
          ]);

          TRACY_PATH = "${tracy-src}/public";
        };

        # For compatibility with older versions of the `nix` binary
        devShell = self.devShells.${system}.default;
      }
    );
}
