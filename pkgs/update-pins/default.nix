# `nix run .#update-pins [name ...]`: bump pins.json to the latest upstream releases.
{
  writeShellApplication,
  coreutils,
  curl,
  gawk,
  gitMinimal,
  gnugrep,
  gnused,
  jq,
  prefetch-npm-deps,
  skopeo,
}:

writeShellApplication {
  name = "update-pins";
  # `nix` is deliberately absent: the host's own Lix on PATH runs `nix flake prefetch`.
  runtimeInputs = [
    coreutils
    curl
    gawk
    gitMinimal
    gnugrep
    gnused
    jq
    prefetch-npm-deps
    skopeo
  ];
  text = builtins.readFile ./update-pins.sh;
}
