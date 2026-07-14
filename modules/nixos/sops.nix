{ config, ... }:

{
  sops.defaultSopsFile = ../../secrets + "/${config.networking.hostName}.yaml";

  sops.secrets.atuin-key.owner = "pengeg";
}
