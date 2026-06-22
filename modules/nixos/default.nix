# Auto-importer: every *.nix under modules/nixos is imported automatically.
# Add a service = drop a file in here; delete a service = remove the file. No list to edit.
#
# Rules (see modules/nixos/_lib for the shared contracts):
#   - This is the ONLY default.nix in the tree — the filter skips every default.nix,
#     so any nested one would be silently dropped. Use named leaf files instead.
#   - Files/dirs whose name starts with "_" are skipped (e.g. _lib/, _scratch.nix).
#     _lib contracts are imported explicitly below as a greppable manifest.
{ lib, ... }:
let
  keep =
    p:
    let
      s = toString p;
      n = baseNameOf s;
    in
    lib.hasSuffix ".nix" n # drops non-nix assets (e.g. the cgit .css)
    && n != "default.nix" # only the root importer is a default.nix
    && !(lib.hasInfix "/_" s); # skip _lib/ and _-prefixed scratch files
in
{
  imports = [
    ./_lib/notify.nix
    ./_lib/proxy.nix
  ]
  ++ lib.filter keep (lib.filesystem.listFilesRecursive ./.);
}
