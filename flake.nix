{
  description = "pengeg's homelab NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nvf = {
      url = "github:notashelf/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    colmena = {
      url = "github:nix-community/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin = {
      url = "github:catppuccin/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Desktop config as a SOURCE TREE (flake = false): we import individual
    # self-contained home modules by store path without inheriting its inputs.
    desktop = {
      url = "github:gegnep/nixos";
      flake = false;
    };
  };
  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      ...
    }@inputs:
    let
      mkModules = hostname: [
        ./hosts/${hostname}
        inputs.disko.nixosModules.disko
        inputs.sops-nix.nixosModules.sops
        home-manager.nixosModules.home-manager
        (
          { config, ... }:
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = {
                inherit inputs;
                hostOptions = config.mySystem;
              };
              backupFileExtension = "bak";
              users.pengeg = import ./modules/home;
            };
          }
        )
      ];

      mkHost =
        {
          hostname,
          system ? "x86_64-linux",
          extraModules ? [ ],
        }:
        nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [ { nixpkgs.hostPlatform = system; } ] ++ mkModules hostname ++ extraModules;
        };
    in
    {
      nixosConfigurations = {
        homelab = mkHost { hostname = "homelab"; };
        ovh = mkHost { hostname = "ovh"; };
        oracle = mkHost {
          hostname = "oracle";
          system = "aarch64-linux";
        };
      };

      # colmena main evaluates `<flake>#colmenaHive` via `nix eval`; the raw
      # `colmena` output is only read under the deprecated --legacy-flake-eval.
      colmenaHive = inputs.colmena.lib.makeHive self.outputs.colmena;

      colmena = {
        meta = {
          nixpkgs = import nixpkgs {
            system = "x86_64-linux";
            config.allowUnfree = true;
          };
          nodeNixpkgs.oracle = import nixpkgs {
            system = "aarch64-linux";
            config.allowUnfree = true;
          };
          specialArgs = { inherit inputs; };
        };

        homelab = {
          imports = mkModules "homelab";
          deployment = {
            allowLocalDeployment = true;
            targetHost = null;
          };
        };
        ovh = {
          imports = mkModules "ovh";
          deployment.targetHost = "ovh";
        };
        oracle = {
          imports = mkModules "oracle";
          deployment = {
            targetHost = "oracle";
            buildOnTarget = true;
          };
        };
      };
    };
}
