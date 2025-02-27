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
      forAllSystems =
        f:
        genAttrs systems (
          system:
          f (
            import nixpkgs {
              localSystem.system = system;
              overlays = [ self.overlays.default ];
            }
          )
        );
    in
    {
      overlays = {
        default = final: prev:  {
          nnl = prev.callPackage ./package.nix { };
        };
      };

      packages = forAllSystems (pkgs: {
        nnl = pkgs.nnl;
        default = self.packages.${pkgs.system}.nnl;
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            nim
            nimble
            openssl
            nix
            nix-prefetch-git
          ];
        };
      });
      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
