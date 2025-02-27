{
  lib,
  buildNimPackage,

  nix,
  nimble,
  nix-prefetch-git,
  openssl,

  makeWrapper,
}:
buildNimPackage (final: {
  pname = "nnl";
  version = "2025.1004";

  src = lib.cleanSource ./.;
  buildInputs = [ openssl ];
  nativeBuildInputs = [ makeWrapper ];
  lockFile = ./lock.json;

  nimFlags = [
    "-d:nnlVersion:${final.version}"
    "-d:nimblePath:${nimble}/bin/nimble"
    "-d:nixPrefetchGitPath:${nix-prefetch-git}/bin/nix-prefetch-git"
    "-d:nixPrefetchUrlPath:${nix}/bin/nix-prefetch-url"
  ];

  doCheck = false;
  postFixup = ''
    wrapProgram $out/bin/nnl \
      --suffix PATH : ${
        lib.makeBinPath [
          nix
          nix-prefetch-git
        ]
      }
  '';

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
