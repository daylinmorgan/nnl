{
  lib,
  buildNimPackage,
  nix,
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
