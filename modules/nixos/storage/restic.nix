{
  config,
  lib,
  mkFailureUnit,
  ...
}:

let
  cfg = config.mySystem.services.restic;
in
{
  options.mySystem.services.restic = {
    enable = lib.mkEnableOption "restic offsite backups to Backblaze B2 (S3 API)";

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "/home"
        "/var/lib"
      ];
      description = "Paths to back up. Tune for the 10 GB free tier (see exclude).";
    };

    exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        # /home noise
        "/home/*/.cache"
        "/home/*/.local/share/Trash"
        "/home/*/downloads"
        "/home/*/videos" # yt-dlp dumps here
        "**/.direnv"
        # /var/lib: big or re-downloadable, or DBs that need dump-based backup
        # NOTE: ollama's store moved to /var/lib/models/ollama (OLLAMA_MODELS).
        # /var/lib/ollama is now just $HOME for the unit (~19M) — keep it.
        "/var/lib/models/ollama" # 136G of blobs, re-pullable
        "/var/lib/models/hf" # 118G of HF base weights, re-downloadable
        "/var/lib/models/.staging" # transient import staging
        "/var/lib/unsloth/studio" # 23G, rebuilt by the image unit
        "/var/lib/unsloth/wheels" # 5.8G of torch wheels, re-downloadable
        "/var/lib/unsloth/cache"
        "/var/lib/unsloth/unsloth-home"
        "/var/lib/containers" # podman storage, re-creatable
        "/var/lib/postgresql" # live PG files are inconsistent — exclude (see note)
        "/var/lib/systemd"
        "/var/lib/nixos"
      ];
      description = "restic --exclude patterns.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.restic-repository = { };
    sops.secrets.restic-password = { };
    sops.secrets.restic-b2-key-id = { };
    sops.secrets.restic-b2-app-key = { };

    programs.fuse.enable = true;

    # B2 talks S3, so restic wants AWS-style env vars. Compose them into the
    # environmentFile from the two discrete secrets.
    sops.templates."restic-b2.env".content = ''
      AWS_ACCESS_KEY_ID=${config.sops.placeholder.restic-b2-key-id}
      AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.restic-b2-app-key}
    '';

    services.restic.backups.b2 = {
      repositoryFile = config.sops.secrets.restic-repository.path;
      passwordFile = config.sops.secrets.restic-password.path;
      environmentFile = config.sops.templates."restic-b2.env".path;
      initialize = true;
      paths = cfg.paths;
      exclude = cfg.exclude;
      timerConfig = {
        OnCalendar = "03:00";
        Persistent = true;
        RandomizedDelaySec = "45min";
      };

      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 6"
      ];
    };

    systemd.services."restic-backups-b2".onFailure = [ "notify-restic-fail.service" ];
    systemd.services.notify-restic-fail = mkFailureUnit {
      name = "restic";
      title = "restic B2 backup FAILED on ${config.networking.hostName}";
      priority = "urgent";
      tags = "rotating_light,floppy_disk";
      body = "Offsite backup failed. Check: journalctl -u restic-backups-b2";
    };
  };
}
