{
  lib,
  buildNpmPackage,
  makeWrapper,
  nodejs,
}:

buildNpmPackage {
  pname = "openai-oauth";
  version = "2.0.0";

  # Stub root package: the real code comes from the registry tarball, which
  # already ships a built dist/. Nothing to compile here.
  src = ./.;
  npmDepsHash = "sha256-BoRjeWQ8P78Qpm26kbq1HlfAXJNWJvxNcnI+SlGEasM=";

  dontNpmBuild = true;
  dontNpmPrune = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib
    cp -r node_modules $out/lib/node_modules
    makeWrapper ${lib.getExe nodejs} $out/bin/openai-oauth \
      --add-flags $out/lib/node_modules/openai-oauth/dist/cli.js
    runHook postInstall
  '';

  meta = {
    description = "Localhost OpenAI-compatible proxy backed by ChatGPT OAuth tokens";
    homepage = "https://github.com/EvanZhouDev/openai-oauth";
    license = lib.licenses.asl20; # npm manifest says Apache-2.0; repo page says AGPL-3.0
    mainProgram = "openai-oauth";
  };
}
