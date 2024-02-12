{
  description = "nim nix lock";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";
  };

  outputs = {
    self,
    nixpkgs,
    systems,
  }: let
    inherit (nixpkgs.lib) genAttrs makeBinPath;
    forAllSystems = f:
      genAttrs (import systems)
      (system:
        f (import nixpkgs {
          localSystem.system = system;
          overlays = [self.overlays.default];
        }));
  in {
    overlays = {
      default = final: _prev: let
        pkgs = final;
      in {
        nnl = pkgs.buildNimPackage {
          pname = "nnl";
          version = "2024.1001";
          src = ./.;
          doCheck = false;
          buildInputs = [pkgs.openssl];
          nativeBuildInputs = [pkgs.makeWrapper];
          postFixup = ''
            wrapProgram $out/bin/nnl \
            --suffix PATH : ${makeBinPath (with pkgs; [nix-prefetch nix-prefetch-git])}
          '';
        };
      };
    };

    packages = forAllSystems (pkgs: {
      default = self.packages.${pkgs.system}.nnl;
      nnl = pkgs.nnl;
    });

    devShells = forAllSystems (pkgs: {
      default = pkgs.mkShell {
        buildInputs = with pkgs; [
          nim
          openssl
          nix-prefetch-git
          nix-prefetch
          # nix # github actions fail using default nix...
        ];
      };
    });
  };
}
