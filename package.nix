{
  lib,
  buildNimPackage,
  nix,
  openssl,
  nimble,
  nix-prefetch-git,
  makeWrapper,
}:
buildNimPackage (final: {
  pname = "nnl";
  version = "2024.1001";

  src = lib.cleanSource ./.;
  buildInputs = [openssl];
  nativeBuildInputs = [makeWrapper];

  doCheck = false;
  postFixup = ''
    wrapProgram $out/bin/nnl \
      --suffix PATH : ${lib.makeBinPath [nix nix-prefetch-git nimble]}
  '';

  meta = with lib; {
    description = "Generate Nix specific lock files for Nim packages from nimble.lock";
    license = licenses.mit;
    homepage = "https://github.com/daylinmorgan/nnl";
    mainProgram = "nnl";
    platforms = lib.platforms.unix;
    maintainers = with maintainers; [daylinmorgan];
  };
  #
})
