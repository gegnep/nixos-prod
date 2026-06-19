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

      loadModels = [
        "llama3.1:8b"
        "qwen2.5-coder:14b"
      ];
    };
  };
}
