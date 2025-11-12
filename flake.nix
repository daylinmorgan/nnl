{
  description = "nim nix lock";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }:
    let
      inherit (nixpkgs.lib) genAttrs;
      systems = [
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forSystem =
        f: system:
        f system (
          import nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
          }
        );
      forAllSystems = f: genAttrs systems (forSystem f);
    in
    {
      overlays = {
        default = final: prev: {
          nnl = prev.callPackage ./package.nix { };
        };
      };

      packages = forAllSystems (
        system: pkgs: {
          nnl = pkgs.nnl;
          default = self.packages.${system}.nnl;
        }
      );

      devShells = forAllSystems (
        _: pkgs: {
          default = pkgs.mkShell {
            packages = with pkgs; [
              nim
              nimble
              openssl
              nix-prefetch-git
            ];
          };
        }
      );
      formatter = forAllSystems (_: pkgs: pkgs.nixfmt-rfc-style);
    };
}
