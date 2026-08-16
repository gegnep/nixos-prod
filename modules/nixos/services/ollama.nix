{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.mySystem.services.ollama;
  packages = {
    cuda = pkgs.ollama-cuda;
    rocm = pkgs.ollama-rocm;
    cpu = pkgs.ollama-cpu;
  };
in
{
  options.mySystem.services.ollama = {
    enable = lib.mkEnableOption "Ollama LLM inference";

    acceleration = lib.mkOption {
      type = lib.types.enum [
        "cuda"
        "rocm"
        "cpu"
      ];
      default = "cuda";
      description = "GPU stack the ollama package is built against";
    };

    rocmOverrideGfx = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "HSA_OVERRIDE_GFX_VERSION, only if ROCm misdetects the GPU";
    };
  };

  config = lib.mkIf cfg.enable {
    services.ollama = {
      enable = true;
      package = packages.${cfg.acceleration};
      rocmOverrideGfx = cfg.rocmOverrideGfx;

      host = "0.0.0.0";
      port = 11434;

      environmentVariables = {
        OLLAMA_FLASH_ATTENTION = "1";
        OLLAMA_KV_CACHE_TYPE = "q8_0";
        OLLAMA_CONTEXT_LENGTH = "8192";
        OLLAMA_KEEP_ALIVE = "10m";
      };
    };
  };
}
