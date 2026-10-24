{ pkgs, lib, ... }:
{
  nix = {
    package = pkgs.lixPackageSets.stable.lix;
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
      trusted-users = [
        "root"
        "pengeg"
      ];
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://cache.nixos-cuda.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
      ];
    };
  };

  nixpkgs.config.allowUnfree = true;

  nixpkgs.overlays = [
    (final: prev: {
      pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
        (pyFinal: pyPrev: {
          # frictionless's checkPhase drifted from pandas 2.3.3/numpy dtype +
          # charset-normalizer behavior after the 2026-06-27 py3.14 bump.
          # Upstream fix not landed. doCheck=false only — no source patch.
          frictionless = pyPrev.frictionless.overridePythonAttrs (_: {
            doCheck = false;
          });
          # posthog is marked broken for mcp >= 2, but mcp is only a test input
          # (nativeCheckInputs); runtime deps are backoff/distro/requests/typing-extensions.
          # Pulled in via open-webui -> chromadb on sidecar.
          posthog =
            prev.lib.warnIf (!(pyPrev.posthog.meta.broken or false))
              "posthog: no longer marked broken upstream; drop the override in core/nix.nix"
              (
                pyPrev.posthog.overridePythonAttrs (old: {
                  doCheck = false;
                  meta = old.meta // {
                    broken = false;
                  };
                })
              );
        })
      ];
    })
  ];

  programs.nh = {
    enable = true;
    flake = "/home/pengeg/nixos";
    clean = {
      enable = true;
      extraArgs = "--keep-since 3d --keep 3";
    };
  };
}
