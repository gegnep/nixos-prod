# Model serving front door. llama-swap answers one OpenAI/Anthropic endpoint and
# starts whichever engine the request's `model` names; one model holds the GPUs
# at a time unless a model file says otherwise.
#
# Engines and globals are declarative (this file; radiance/maya later). Models are
# runtime state: one YAML file per model in /var/lib/llama-swap/models.d, written
# by `ai` and hot-reloaded by llama-swap (-config-dir + -watch-config).
#
# Storage rule: everything re-downloadable lives under /var/lib/models/cache
# (the @models subvolume: nodatacow, outside btrbk, excluded from restic).
{
  config,
  lib,
  pkgs,
  mkFailureUnit,
  ...
}:

let
  cfg = config.mySystem.services.inference;
  stateDir = "/var/lib/llama-swap";
  modelsDir = "${stateDir}/models.d";
  cacheDir = "/var/lib/models/cache";
  yaml = pkgs.formats.yaml { };
  llamaSwap = config.services.llama-swap.package;

  llamaCpp =
    {
      rocm = pkgs.llama-cpp-rocm;
      cuda = pkgs.llama-cpp-cuda;
      cpu = pkgs.llama-cpp;
    }
    .${cfg.acceleration};

  # Model files reference macros, never store paths, so an engine bump does not
  # touch the registry. ${PORT} and ${MODEL_ID} are llama-swap built-ins.
  settings = lib.recursiveUpdate {
    healthCheckTimeout = 900; # Maya's cold start is minutes
    sendLoadingState = true; # loading progress in the reasoning stream keeps clients patient
    startPort = 10001;
    unloadTimeout = 30;
    logLevel = "info";
    macros = {
      llama = "${lib.getExe' llamaCpp "llama-server"} --host 127.0.0.1 --port \${PORT} --alias \${MODEL_ID} --no-webui";
    }
    // cfg.macros;
  } cfg.settings;

  # Validated at build time. Model files are validated by `ai` against this
  # same file before they are installed.
  baseConfig =
    pkgs.runCommandLocal "llama-swap-base.yaml" { nativeBuildInputs = [ llamaSwap ]; }
      ''
        cp ${yaml.generate "llama-swap-base-unchecked.yaml" settings} $out
        llama-swap -validate -config $out
      '';

  ai = pkgs.writeShellApplication {
    name = "ai";
    runtimeInputs = [
      llamaSwap
      pkgs.coreutils
      pkgs.curl
      pkgs.findutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.gum
      pkgs.jq
      pkgs.python3Packages.huggingface-hub # `hf`
      pkgs.util-linux # column
      pkgs.yq-go
    ];
    runtimeEnv = {
      AI_URL = "http://127.0.0.1:${toString cfg.port}";
      AI_BASE_CONFIG = "${baseConfig}";
      AI_MODELS_DIR = modelsDir;
      AI_CACHE = cacheDir;
      AI_ENGINES = lib.concatStringsSep " " cfg.engines;
      AI_STUDIO = if config.mySystem.services.unsloth.enable then "1" else "0";
      AI_OWNER = "llama-swap";
      AI_SUDO = "sudo";
    };
    text = builtins.readFile ./ai.sh;
  };
in
{
  options.mySystem.services.inference = {
    enable = lib.mkEnableOption "llama-swap model front door with llama.cpp";

    acceleration = lib.mkOption {
      type = lib.types.enum [
        "rocm"
        "cuda"
        "cpu"
      ];
      description = "GPU stack llama.cpp is built against.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8180;
      description = "llama-swap listen port (OpenAI and Anthropic APIs, UI at /ui/).";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "tailscale0 is a trusted interface; every other interface stays firewalled.";
    };

    macros = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        llama-dual = "\${llama} -sm layer -ts 1,1";
      };
      description = "Extra llama-swap macros for model files, merged over the built-in `llama`.";
    };

    settings = lib.mkOption {
      type = yaml.type;
      default = { };
      description = "Overrides for the llama-swap base config. Globals only: models live in models.d.";
    };

    engines = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      internal = true;
      description = "Engine macros `ai add --engine` accepts. Engine modules append to it.";
    };
  };

  config = lib.mkIf cfg.enable {
    mySystem.services.inference.engines = [ "llama" ];

    # Fresh Open WebUI databases get this host's front door as a connection.
    mySystem.services.open-webui.openaiConnections = [
      { url = "http://127.0.0.1:${toString cfg.port}/v1"; }
    ];

    users.users.llama-swap = {
      isSystemUser = true;
      group = "llama-swap";
      home = stateDir;
    };
    users.groups.llama-swap = { };

    services.llama-swap = {
      enable = true;
      port = cfg.port;
      inherit (cfg) listenAddress;
      # Unused by our ExecStart; kept equal to the base config so the module stays coherent.
      inherit settings;
    };

    systemd.services.llama-swap = {
      # The module's default sits on the root subvolume under /var/cache.
      environment.LLAMA_CACHE = lib.mkForce "${cacheDir}/llama";
      unitConfig.OnFailure = [ "notify-llama-swap-fail.service" ];
      serviceConfig = {
        # The module's ExecStart knows only -config; models.d needs -config-dir.
        ExecStart = lib.mkForce (
          lib.escapeShellArgs [
            (lib.getExe llamaSwap)
            "--listen=${cfg.listenAddress}:${toString cfg.port}"
            "--config=${baseConfig}"
            "--config-dir=${modelsDir}"
            "--watch-config"
          ]
        );
        # Static user: owns models.d and the cache across restarts, and the
        # engine polkit rule (homelab) matches on its name.
        DynamicUser = lib.mkForce false;
        User = "llama-swap";
        Group = "llama-swap";
        SupplementaryGroups = [
          "render"
          "video"
        ];
        StateDirectory = "llama-swap";
        ReadWritePaths = [ "${cacheDir}/llama" ];
      };
    };

    systemd.services.notify-llama-swap-fail = mkFailureUnit {
      name = "llama-swap";
      title = "llama-swap failed";
      body = "llama-swap.service entered failed state; check journalctl -u llama-swap";
      tags = "warning";
    };

    systemd.tmpfiles.rules = [
      "d ${cacheDir} 0755 root root"
      "d ${cacheDir}/llama 0755 llama-swap llama-swap"
      "d ${cacheDir}/hf-home 0755 llama-swap llama-swap"
      "d ${modelsDir} 0755 llama-swap llama-swap"
      # llama-swap 262's dir watcher misses the change when models.d goes empty
      # (verified 2026-10-20). A comment-only file parses to nothing and keeps it
      # non-empty; ids cannot start with "_", so it never collides with a model.
      "f ${modelsDir}/_keep.yaml 0644 llama-swap llama-swap - # placeholder, see inference.nix"
    ];

    environment.systemPackages = [ ai ];

    mySystem.proxy.vhosts.llm = {
      sub = "llm";
      upstream = "127.0.0.1:${toString cfg.port}";
      dashboard = {
        name = "llama-swap";
        description = "Model front door";
        path = "/ui/";
      };
    };
  };
}
