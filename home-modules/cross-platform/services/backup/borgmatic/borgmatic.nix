# borgmatic backups module.
#
# Provides a Linux (systemd) and a Darwin scheduler with separate syntax for each.
#
# The config files are written directly, not through
# programs.borgmatic.backups.
#
# Provides alerting OnFailure on the unit for a failed run, and a daily stale check
# against a success stamp for a run that never happened.
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.services.backup;

  repoCheck = pkgs.writeShellApplication {
    name = "backup-repo-check";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./repo-check.sh;
  };

  # Test to ensure that the repository exists and is mounted.
  mkGuard = repository: [
    {
      before = "action";
      when = [
        "create"
        "prune"
        "compact"
        "check"
      ];
      run = [
        # A trailing slash on the option yields "//config", which POSIX
        # tolerates. The message names the exact path tested so a false
        # alarm shows its own cause in the journal.
        "test -f ${repository}/config || { echo 'borgmatic: ${repository}/config missing: repository not initialised, or mount down' >&2; exit 1; }"
      ];
    }
  ];

  # Flat schema output for borgmatic 2.x.
  mkBackupFile =
    {
      repository,
      guard ? false,
    }:
    builtins.toJSON (
      {
        repositories = [ { path = repository; } ];
        inherit (cfg) patterns;

        keep_daily = cfg.retention.daily;
        keep_weekly = cfg.retention.weekly;
        keep_monthly = cfg.retention.monthly;
        keep_yearly = cfg.retention.yearly;

        inherit (cfg) checks;

      }
      // lib.optionalAttrs (cfg.passphraseFile != null) {
        encryption_passcommand = "${pkgs.coreutils}/bin/cat ${cfg.passphraseFile}";
      }
      // lib.optionalAttrs guard {
        commands = mkGuard repository;
      }
      // cfg.monitoring
    );

  # Alerting for failed backup attempts (Linux only)
  #
  stampFile = "${config.xdg.stateHome}/borgmatic/last-success";

  alert = pkgs.writeShellApplication {
    name = "borgmatic-alert";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      # $1: message. cfg.alerts.command receives it as its final argument.
      exec ${cfg.alerts.command} "$1"
    '';
  };

  recordSuccess = pkgs.writeShellApplication {
    name = "borgmatic-record-success";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      mkdir -p "$(dirname "${stampFile}")"
      touch "${stampFile}"
    '';
  };

  staleCheck = pkgs.writeShellApplication {
    name = "borgmatic-stale-check";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      stamp="${stampFile}"
      max="${toString cfg.alerts.staleAfterDays}"

      if [ ! -f "$stamp" ]; then
        exec ${alert}/bin/borgmatic-alert "no successful backup has been recorded on this host"
      fi

      age=$(( ( $(date +%s) - $(stat -c %Y "$stamp") ) / 86400 ))
      if [ "$age" -ge "$max" ]; then
        exec ${alert}/bin/borgmatic-alert "last successful backup was $age days ago (limit $max)"
      fi
    '';
  };

in
{
  options.nixSpace.services.backup = {
    enable = lib.mkEnableOption "borgmatic backups";

    patterns = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "R /home/user"
        "- /home/user/.cache"
        "- **/node_modules"
      ];
      description = ''
        borg patterns describing what to back up.

        Patterns are not source directories: each line starts with a marker - R
        for a root to recurse into, `-` to exclude, `+` to include, and they are
        evaluated in order, so an exclusion must come after the root it
        applies to.
      '';
    };

    guardRepositories = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Refuse to run when a local repository is missing its `config` file.

        Borg will write an empty mountpoint for a repository on a network mount 
        when the mount is down. This will write to the local filesystem and shadow
        the mount when it is online. 

        Only local (NFS) repositories are guarded: a remote one is reached over
        ssh, where a connection failure is already an error rather than a
        silent success.
      '';
    };

    passphraseFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/user/1000/agenix/borg-passphrase";
      description = ''
        File containing the repository passphrase, read at backup time.

        This is a path, not the passphrase: the value is stored in the Nix store.
        An agenix or sops path is the intended shape.
      '';
    };

    encryptedBackup = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Require repositories to be encrypted.

        This is option is enforced by an assertion.        
        Set to false where an unencrypted repository is a deliberate choice. 
        Borg can only set encryption for new repositories, it cannot encrypted
        previously unencrypted repos.
      '';
    };

    local = {
      repository = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/mnt/backup/borg";
        description = ''
          Path to the repository location to store backups.
        '';
      };
    };

    remote = {
      host = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "backupsvr.lan";
        description = ''
          SSH host for the remote repository, or null for none.

          A host or an ssh_config alias - borg invokes ssh, so anything ssh
          resolves works, including a Host block with a key and a port.
        '';
      };

      path = lib.mkOption {
        type = lib.types.str;
        default = "./Borg";
        description = ''
          Repository path on the remote host.

          The leading `./` is borg's convention for "relative to the login
          user's home". An absolute path can also be used.
        '';
      };
    };

    retention = {
      daily = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 60;
        description = "Daily archives to keep.";
      };
      weekly = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 52;
        description = "Weekly archives to keep.";
      };
      monthly = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 36;
        description = "Monthly archives to keep.";
      };
      yearly = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 20;
        description = ''
          Yearly archives to keep.

          Retention is applied by `borgmatic prune`, which runs as part of a
          scheduled backup, so these take effect on the next run, not at
          rebuild.
        '';
      };
    };

    monitoring = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      example = lib.literalExpression ''
        {
          healthchecks.ping_url = "https://hc.p22/ping/…";
          ntfy = { topic = "backups"; server = "https://ntfy.p22"; states = [ "fail" ]; };
        }
      '';
      description = ''
        borgmatic monitoring hooks, merged verbatim into the top level of
        every generated config (borgmatic 2.x keeps them flat). This is the
        fleet answer once a healthchecks or ntfy server exists: a central
        dead man's switch that notices a host that stopped reporting.

        The local alerts below are the offline fallback and stay on either
        way; the two are not exclusive.
      '';
    };

    alerts = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Local alerting for the scheduled job. Linux only.

          Two mechanisms: the borgmatic unit gets OnFailure= pointing at an
          alert unit, so a failed run notifies at once; and a daily timer
          checks when the last run succeeded, so a run that never started
          (ConditionACPower, a timer that could not fire, a unit someone
          disabled) is noticed after staleAfterDays.
        '';
      };

      staleAfterDays = lib.mkOption {
        type = lib.types.ints.positive;
        default = 2;
        description = ''
          Days without a recorded success before the stale check alerts.
          Two tolerates one skipped night without noise.
        '';
      };

      checkAt = lib.mkOption {
        type = lib.types.str;
        default = "12:00";
        description = ''
          When the stale check runs, in systemd OnCalendar syntax. Midday by
          default so the alert lands while someone is at the machine, not
          at the same hour the backup itself runs.
        '';
      };

      command = lib.mkOption {
        type = lib.types.str;
        default = "${pkgs.libnotify}/bin/notify-send --urgency=critical --app-name=borgmatic Backup";
        defaultText = lib.literalExpression ''"''${pkgs.libnotify}/bin/notify-send --urgency=critical --app-name=borgmatic Backup"'';
        description = ''
          Command that delivers an alert; the message is appended as its
          final argument. The default is a desktop notification, which
          reaches a user session's notification daemon through the user
          bus that systemd provides to user services.

          A headless host needs something else here: an ntfy publish, a
          mail pipe, or a script. Anything that takes the message as $1.
        '';
      };
    };

    schedule = {
      systemd = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        example = "Mon *-*-* 02:00:00";
        description = ''
          When to run, in systemd OnCalendar syntax. Linux only.

          This is separate from the Darwin schedule because the two formats have no
          overlap: systemd takes a calendar expression, launchd takes a
          dictionary of components.
        '';
      };

      darwinHour = lib.mkOption {
        type = lib.types.ints.between 0 23;
        default = 2;
        description = "Hour to run at on Darwin.";
      };

      darwinMinute = lib.mkOption {
        type = lib.types.ints.between 0 59;
        default = 0;
        description = ''
          Minute to run at on Darwin.

          launchd runs a missed job when the machine wakes, unlike a systemd
          timer without Persistent, so a laptop asleep at this time still
          gets its backup.
        '';
      };
    };

    # Periodic backup validation check
    checks = lib.mkOption {
      type = lib.types.listOf lib.types.anything;
      default = [
        {
          name = "repository";
          frequency = "4 weeks";
        }
      ];
      example = [
        {
          name = "repository";
          frequency = "4 weeks";
        }
        {
          name = "archives";
          frequency = "6 months";
        }
      ];
      description = ''
        How often borgmatic runs consistency checks for its repos.

        A check runs as part of a scheduled backup once its frequency has
        elapsed, not on its own timer.

        "repository" verifies structure and is cheap. "archives" reads every
        archive's data, which is thorough but slower.

        An empty list disables verification entirely, which means corruption
        will only be discovered when a restore fails.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.local.repository != null || cfg.remote.host != null;
        message = ''
          nixSpace.services.backup is enabled with no repository: set
          local.repository, remote.host, or both.

          borgmatic with no repository configured runs and archives nothing.
        '';
      }
      {
        assertion = cfg.patterns != [ ];
        message = ''
          nixSpace.services.backup.patterns is empty, so the scheduled job
          would archive nothing.

          Patterns start with a marker: "R /home/you" to recurse into a root,
          "- /home/you/.cache" to exclude.
        '';
      }
      {
        assertion = !cfg.encryptedBackup || cfg.passphraseFile != null;
        message = ''
          nixSpace.services.backup.encryptedBackup is true but no
          passphraseFile is set: the repository would be unencrypted.
          ...
        '';
      }
    ];

    home.packages = [
      repoCheck
      pkgs.borgbackup
    ];

    # Linux: a systemd timer, from the home-manager module.
    services.borgmatic = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      enable = true;
      frequency = cfg.schedule.systemd;
    };

    systemd.user = lib.mkIf (pkgs.stdenv.hostPlatform.isLinux && cfg.alerts.enable) {
      # Additions to home-manager's unit: the success stamp, and an
      # immediate alert on failure. ExecStartPost only runs when ExecStart
      # exited 0, which is exactly the definition of success wanted here.
      services = {
        borgmatic = {
          Unit.OnFailure = [ "borgmatic-alert.service" ];
          Service.ExecStartPost = "${recordSuccess}/bin/borgmatic-record-success";
        };

        borgmatic-alert = {
          Unit.Description = "Alert on a failed borgmatic run";
          Service = {
            Type = "oneshot";
            ExecStart = "${alert}/bin/borgmatic-alert 'backup FAILED — journalctl --user -u borgmatic.service'";
          };
        };

        borgmatic-stale = {
          Unit.Description = "Alert when no backup has succeeded recently";
          Service = {
            Type = "oneshot";
            ExecStart = "${staleCheck}/bin/borgmatic-stale-check";
          };
        };
      };

      timers.borgmatic-stale = {
        Unit.Description = "Daily check that a backup succeeded recently";
        Timer = {
          OnCalendar = cfg.alerts.checkAt;
          Persistent = true;
        };
        Install.WantedBy = [ "timers.target" ];
      };
    };

    # Darwin: a launchd agent, with its own schedule format.
    launchd.agents.borgmatic = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      enable = true;
      config = {
        ProgramArguments = [ "${pkgs.borgmatic}/bin/borgmatic" ];

        StartCalendarInterval = [
          {
            Hour = cfg.schedule.darwinHour;
            Minute = cfg.schedule.darwinMinute;
          }
        ];

        # Both streams to one file: borgmatic writes progress to stderr and
        # results to stdout.
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/borgmatic.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/borgmatic.log";
      };
    };

    programs.borgmatic = {
      enable = true;

      # This installs borgmatic and, on Linux, gives services.borgmatic
      # something to schedule.
      backups = { };
    };

    xdg.configFile =
      lib.optionalAttrs (cfg.local.repository != null) {
        "borgmatic.d/local.yaml".text = mkBackupFile {
          repository = cfg.local.repository;
          guard = cfg.guardRepositories;
        };
      }
      // lib.optionalAttrs (cfg.remote.host != null) {
        "borgmatic.d/remote.yaml".text = mkBackupFile {
          repository = "ssh://${cfg.remote.host}/${cfg.remote.path}";
          # Not guarded: a remote repository is reached over ssh, where a
          # connection failure is already an error rather than a silent write
          # to the wrong place.
        };
      };
  };
}
