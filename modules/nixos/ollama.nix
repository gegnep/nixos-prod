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

      # Q4_K_M for > 12b, Q5_K_M for <= 12b
      loadModels = [
        "qwen3:14b" # general purpose
        "qwen2.5-coder:14b" # coder
        "deepseek-r1:14b" # deep reasoning
        "gemma3:12b" # multimodal
        "mistral-nemo:12b-instruct-2407-q5_K_M" # 128k native context

        # fast models
        "qwen3:8b"
        "mistral:7b"
        "gemma3:4b"
      ];
    };
  };
}
