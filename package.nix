{
  lib,
  buildNimPackage,

  nimble,
  nix-prefetch-git,
  openssl,
}:
buildNimPackage (final: {
  pname = "nnl";
  version = "2025.1004";

  src = lib.cleanSource ./.;

  buildInputs = [
    openssl
    nimble
    nix-prefetch-git
  ];

  lockFile = ./lock.json;

  nimFlags = [
    "-d:nnlVersion:${final.version}"
    "-d:nimblePath:${nimble}/bin/nimble"
    "-d:nixPrefetchGitPath:${nix-prefetch-git}/bin/nix-prefetch-git"
  ];

  doCheck = false;

  meta = with lib; {
    description = "Generate Nix specific lock files for Nim packages from nimble.lock";
    license = licenses.mit;
    homepage = "https://github.com/daylinmorgan/nnl";
    mainProgram = "nnl";
    platforms = platforms.unix;
    maintainers = with maintainers; [ daylinmorgan ];
  };
  #
})
