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
      default = final: _prev: {
        nnl = final.callPackage ./package.nix {};
      };
    };

    packages = forAllSystems (pkgs: {
      nnl = pkgs.nnl;
      default = self.packages.${pkgs.system}.nnl;
    });

    devShells = forAllSystems (pkgs: {
      default = pkgs.mkShell {
        buildInputs = with pkgs; [
          nim
          nimble
          openssl
          nix
          nix-prefetch-git
        ];
      };
    });
  };
}
