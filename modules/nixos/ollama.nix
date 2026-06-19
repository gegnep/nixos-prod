{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.mySystem.services.ollama;
in
{
  options.mySystem.services.ollama.enable = lib.mkEnableOption "Ollama LLM inference (CUDA)";

  config = lib.mkIf cfg.enable {
    services.ollama = {
      enable = true;
      package = pkgs.ollama-cuda;

      host = "0.0.0.0";
      port = 11434;

      environmentVariables = {
        OLLAMA_FLASH_ATTENTION = "1"; # prereq for KV quant; free win
        OLLAMA_KV_CACHE_TYPE = "q8_0"; # ~halve KV cache, negligible quality hit
        OLLAMA_CONTEXT_LENGTH = "8192";
        OLLAMA_KEEP_ALIVE = "30m"; # default unloads after 5m
      };

      loadModels = [
        "mistral-small3.2:24b" # chunkiest model we can run on this jawn
        "gemma4:e4b" # multimodal, possibly "best" model here rn
        "qwen3.5:9b" # latest qwen model that fits on the 3060
        "qwen3.5:2b" # use for anything on the site that dosent need any other model
      ];
    };
  };
}
