{ config, ... }:

{
  sops.defaultSopsFile = ../../secrets + "/${config.networking.hostName}.yaml";
}
