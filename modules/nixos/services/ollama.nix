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

  # Shared bash preamble for both helpers. Pins the endpoint (an inherited
  # OLLAMA_HOST must not redirect import/prune elsewhere) and validates a
  # derived model name: basename, strip -GGUF, lowercase, then reject
  # anything that is not a safe single-component name.
  helperLib = ''
    export OLLAMA_HOST=127.0.0.1:11434
    gguf_root=/var/lib/models/gguf

    derive_name() {
      local n
      n=$(basename -- "$1")
      n=''${n%-GGUF}
      n=''${n%-gguf}
      n=''${n,,}
      case $n in
        *[!a-z0-9._-]* | "" | . | .. | -* | .*)
          echo "error: cannot derive a safe model name from '$1'; pass one explicitly" >&2
          return 1
          ;;
      esac
      printf '%s\n' "$n"
    }

    validate_name() {
      # override names skip derive_name; a leading dash would reach the
      # ollama CLI as a flag
      case $1 in
        *[!A-Za-z0-9._:-]* | "" | -*)
          echo "error: invalid model name: $1" >&2
          return 1
          ;;
      esac
    }
  '';

  ollamaImport = pkgs.writeShellApplication {
    name = "ollama-import";
    runtimeInputs = [
      packages.${cfg.acceleration}
      pkgs.coreutils
      pkgs.findutils
    ];
    text = ''
      # Import Studio GGUF exports from /var/lib/models/gguf into ollama.
      # No args: scan every run dir, import what is ready and new.
      # One arg (+ optional model name): import that run, overwriting.
      shopt -s nullglob
      ${helperLib}

      if [ $# -gt 2 ]; then
        echo "usage: ollama-import [run-dir [model-name]]" >&2
        exit 1
      fi

      has_model_gguf() {
        # true if the dir holds a .gguf that is neither mmproj nor adapter
        local f
        for f in "$1"/*.gguf; do
          case $(basename -- "$f") in
            *mmproj* | *-lora-*) continue ;;
            *) return 0 ;;
          esac
        done
        return 1
      }

      still_writing() {
        # any .gguf modified in the last minute: Studio may not be done.
        # A failed find counts as still-writing: skip, never import blind.
        local out
        out=$(find "$1" -maxdepth 1 -name '*.gguf' -mmin -1 -print -quit) || return 0
        [ -n "$out" ]
      }

      import_dir() {
        # ollama create's FROM . uploads every file in the dir, and Studio's
        # export_metadata.json breaks its GGUF parsing (verified 2026-08-23).
        # Stage only the Modelfile and ggufs, same fs, then create from there.
        local dir=$1 name=$2 staging
        staging=$(mktemp -d /var/lib/models/.staging/import-XXXXXX) || return 1
        if cp -- "$dir/Modelfile" "$dir"/*.gguf "$staging/" \
          && (cd "$staging" && ollama create "$name"); then
          rm -rf -- "$staging"
          echo "imported: $name  (from $dir)"
        else
          rm -rf -- "$staging"
          return 1
        fi
      }

      if [ $# -eq 0 ]; then
        failed=0
        for dir in "$gguf_root"/*/; do
          dir=''${dir%/}
          run=$(basename -- "$dir")
          if ! has_model_gguf "$dir"; then
            echo "skip: $run (no merged .gguf)"
          elif [ ! -f "$dir/Modelfile" ]; then
            echo "skip: $run (no Modelfile)"
          elif still_writing "$dir"; then
            echo "skip: $run (gguf modified <60s ago, export may be running)"
          elif ! name=$(derive_name "$dir"); then
            echo "skip: $run (underivable name; import explicitly)"
          elif ollama show "$name" >/dev/null 2>&1; then
            echo "skip: $run (already imported as $name)"
          elif ! import_dir "$dir" "$name"; then
            echo "FAILED: $run" >&2
            failed=1
          fi
        done
        exit "$failed"
      else
        dir=$1
        [ -d "$dir" ] || dir="$gguf_root/$1"
        if [ ! -d "$dir" ]; then
          echo "error: no run dir: $1" >&2
          exit 1
        fi
        if [ ! -f "$dir/Modelfile" ]; then
          echo "error: $dir has no Modelfile." >&2
          echo "Studio writes one for merged GGUF exports; re-export, or write one by hand (FROM . plus the chat TEMPLATE)." >&2
          exit 1
        fi
        name=''${2:-$(derive_name "$dir")}
        validate_name "$name"
        import_dir "$dir" "$name"
      fi
    '';
  };

  ollamaPrune = pkgs.writeShellApplication {
    name = "ollama-prune";
    runtimeInputs = [
      packages.${cfg.acceleration}
      pkgs.coreutils
      pkgs.curl
    ];
    text = ''
      # Remove a fine-tune from both sides: ollama store and gguf run dir.
      ${helperLib}

      if [ $# -lt 1 ] || [ $# -gt 2 ]; then
        echo "usage: ollama-prune <run-dir-name> [model-name]" >&2
        exit 1
      fi
      if [ "$(id -u)" -ne 0 ]; then
        echo "error: run with sudo (deletes files owned by uid 1001)" >&2
        exit 1
      fi

      run=$(basename -- "$1")
      case $run in
        *[!A-Za-z0-9._-]* | "" | . | .. | -*)
          echo "error: invalid run name: $1" >&2
          exit 1
          ;;
      esac
      dir="$gguf_root/$run"
      name=''${2:-$(derive_name "$run")}
      validate_name "$name"

      # Classify by HTTP status BEFORE the irreversible rm below: only a
      # positive 404 counts as not-found; a dead server, timeout, or any
      # other status aborts. ($name is validated above, safe in the JSON.)
      code=$(curl -sS --max-time 10 -o /dev/null -w "%{http_code}" \
        -X POST "http://$OLLAMA_HOST/api/show" -d "{\"model\":\"$name\"}") || {
        echo "error: ollama server unreachable at $OLLAMA_HOST; not deleting anything" >&2
        exit 1
      }
      case $code in
        200)
          ollama rm "$name"
          echo "removed model: $name"
          ;;
        404)
          echo "note: model $name not in ollama"
          ;;
        *)
          echo "error: ollama /api/show returned $code for $name; aborting" >&2
          exit 1
          ;;
      esac
      if [ -d "$dir" ]; then
        rm -rf -- "$dir"
        echo "pruned dir: $dir"
      else
        echo "note: no dir $dir"
      fi
    '';
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

      # Static user: the store lives outside StateDirectory, and a
      # DynamicUser uid cannot own a pre-created /var/lib/models/ollama.
      user = "ollama";
      group = "ollama";
      modelsDir = "/var/lib/models/ollama";

      environmentVariables = {
        OLLAMA_FLASH_ATTENTION = "1";
        OLLAMA_KV_CACHE_TYPE = "q8_0";
        OLLAMA_KEEP_ALIVE = "10m";
      };
    };

    # nixpkgs sets DynamicUser=true unconditionally (verified on master);
    # user/group above only add the static accounts. Without this,
    # StateDirectory stays under /var/lib/private via symlink.
    systemd.services.ollama.serviceConfig.DynamicUser = lib.mkForce false;

    systemd.tmpfiles.rules = [
      "d /var/lib/models/ollama 0755 ollama ollama"
      # import staging: same fs as gguf/, world-writable like /tmp
      "d /var/lib/models/.staging 1777 root root"
    ];

    environment.systemPackages = [
      ollamaImport
      ollamaPrune
    ];
  };
}
