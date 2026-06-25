# Himmelblau workspace: PAM, NSS, broker, daemon, user-map, browser SSO.
#
# Uses `pkgs.himmelblauTpm` (added by `overlays.default` in the flake)
# to replace upstream's stock Himmelblau packages with the TPM-enabled
# rebuild from `pkgs/himmelblau-tpm/`. The upstream
# `services.himmelblau.*` module (imported at the flake level) provides
# everything else.
#
# Intune-compliance shimming lives in `intune-compliance.nix`. PAM
# wiring is small enough to live here.
{ lib, pkgs, config, ... }:

let
  cfg = config.entrablau;
  himmelblauTpm = pkgs.himmelblauTpm;
  defaultMappedUpn =
    if cfg.localUser != null && builtins.hasAttr cfg.localUser cfg.userMap
    then builtins.getAttr cfg.localUser cfg.userMap
    else "";
  defaultLocalUser =
    if cfg.localUser != null then cfg.localUser else "";
  ssoRuntimeInputs = [
    pkgs.coreutils
    pkgs.glibc
    pkgs.gnugrep
    pkgs.gnused
    pkgs.systemd
  ];
  ssoDiagnosticsCommon = ''
    DEFAULT_UPN=${lib.escapeShellArg defaultMappedUpn}
    DEFAULT_LOCAL_USER=${lib.escapeShellArg defaultLocalUser}
    BROKER_BUS_NAME=com.microsoft.identity.broker1
    BROKER_OBJECT_PATH=/com/microsoft/identity/broker1

    usage_common() {
      printf '  --upn <upn>          Entra UPN to check with NSS (default: configured entrablau.localUser mapping, if any)\n'
      printf '  --local-user <name>  Local user to resolve through /etc/himmelblau/user-map when --upn is omitted\n'
    }

    parse_common_args() {
      upn=$DEFAULT_UPN
      local_user=$DEFAULT_LOCAL_USER
      timeout=60
      interval=2
      quiet=0
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --upn)
            shift
            if [ "$#" -eq 0 ]; then
              printf 'ERROR: --upn requires a value\n' >&2
              exit 2
            fi
            upn=$1
            ;;
          --local-user)
            shift
            if [ "$#" -eq 0 ]; then
              printf 'ERROR: --local-user requires a value\n' >&2
              exit 2
            fi
            local_user=$1
            ;;
          --timeout)
            shift
            if [ "$#" -eq 0 ]; then
              printf 'ERROR: --timeout requires seconds\n' >&2
              exit 2
            fi
            timeout=$1
            ;;
          --interval)
            shift
            if [ "$#" -eq 0 ]; then
              printf 'ERROR: --interval requires seconds\n' >&2
              exit 2
            fi
            interval=$1
            ;;
          --quiet)
            quiet=1
            ;;
          -h|--help)
            usage
            exit 0
            ;;
          *)
            printf 'ERROR: unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
        esac
        shift
      done

      case "$timeout" in
        ""|*[!0-9]*)
          printf 'ERROR: --timeout must be a non-negative integer\n' >&2
          exit 2
          ;;
      esac
      case "$interval" in
        ""|*[!0-9]*)
          printf 'ERROR: --interval must be a non-negative integer\n' >&2
          exit 2
          ;;
      esac
      if [ "$interval" -eq 0 ]; then
        interval=1
      fi

      if [ -z "$upn" ] && [ -n "$local_user" ]; then
        mapped=$(lookup_upn_for_local "$local_user")
        if [ -n "$mapped" ]; then
          upn=$mapped
        fi
      fi
    }

    lookup_upn_for_local() {
      wanted=$1
      if [ ! -r /etc/himmelblau/user-map ]; then
        return 0
      fi
      while IFS=: read -r local mapped_upn rest; do
        if [ "$local" = "$wanted" ] && [ -n "$mapped_upn" ] && [ -z "$rest" ]; then
          printf '%s\n' "$mapped_upn"
          return 0
        fi
      done < /etc/himmelblau/user-map
    }

    report() {
      level=$1
      shift
      if [ "$silent" -eq 1 ]; then
        return 0
      fi
      if [ "$quiet" -eq 0 ] || [ "$level" = FAIL ]; then
        printf '%s %s\n' "$level" "$*"
      fi
    }

    fail() {
      failures=$((failures + 1))
      report FAIL "$@"
    }

    unit_exists() {
      unit=$1
      run_systemctl list-unit-files "$unit" --no-legend --no-pager 2>/dev/null | grep -q . \
        || run_systemctl list-units --all "$unit" --no-legend --no-pager 2>/dev/null | grep -q .
    }

    find_executable() {
      name=$1
      found=$(command -v "$name" || true)
      if [ -n "$found" ] && [ -x "$found" ]; then
        printf '%s\n' "$found"
        return 0
      fi
      if [ -x "/run/current-system/sw/bin/$name" ]; then
        printf '%s\n' "/run/current-system/sw/bin/$name"
        return 0
      fi
      return 1
    }

    run_systemctl() {
      systemctl_bin=$(find_executable systemctl || true)
      if [ -z "$systemctl_bin" ]; then
        return 127
      fi
      "$systemctl_bin" "$@"
    }

    run_busctl() {
      busctl_bin=$(find_executable busctl || true)
      if [ -z "$busctl_bin" ]; then
        return 127
      fi
      "$busctl_bin" "$@"
    }

    check_tasks_active() {
      if unit_exists himmelblaud-tasks.service; then
        run_systemctl is-active --quiet himmelblaud-tasks.service
      else
        return 2
      fi
    }

    check_broker_bus() {
      if ! run_busctl --user --no-pager list >/dev/null 2>&1; then
        return 1
      fi
      if run_busctl --user --no-pager list 2>/dev/null \
        | grep -q "^''${BROKER_BUS_NAME}[[:space:]]"; then
        return 0
      fi
      run_busctl --user call "$BROKER_BUS_NAME" "$BROKER_OBJECT_PATH" \
        org.freedesktop.DBus.Peer Ping >/dev/null 2>&1
    }

    check_sso_binary() {
      sso_bin=$(find_executable linux-entra-sso || true)
      if [ -z "$sso_bin" ]; then
        return 1
      fi
      "$sso_bin" --help >/dev/null 2>&1
    }

    check_aad_status() {
      aad_bin=$(find_executable aad-tool || true)
      if [ -z "$aad_bin" ]; then
        return 1
      fi
      "$aad_bin" status >/dev/null 2>&1
    }

    check_nss_upn() {
      getent_bin=$(find_executable getent || true)
      if [ -z "$getent_bin" ]; then
        return 1
      fi
      "$getent_bin" passwd "$upn" >/dev/null 2>&1
    }

    find_valid_firefox_manifest() {
      for manifest in \
        "/run/current-system/sw/lib/mozilla/native-messaging-hosts/linux_entra_sso.json" \
        "/etc/profiles/per-user/''${USER:-}/lib/mozilla/native-messaging-hosts/linux_entra_sso.json" \
        "/nix/var/nix/profiles/default/lib/mozilla/native-messaging-hosts/linux_entra_sso.json" \
        "/etc/firefox/native-messaging-hosts/linux_entra_sso.json" \
        "/usr/lib/mozilla/native-messaging-hosts/linux_entra_sso.json" \
        "/usr/lib64/mozilla/native-messaging-hosts/linux_entra_sso.json"
      do
        if [ -r "$manifest" ]; then
          host_path=$(sed -n 's/^[[:space:]]*"path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | head -n 1)
          if [ -n "$host_path" ] && [ -x "$host_path" ]; then
            printf '%s\n' "$manifest"
            return 0
          fi
        fi
      done
      return 1
    }

    run_checks() {
      failures=0

      if run_systemctl is-active --quiet himmelblaud.service; then
        report PASS 'himmelblaud.service is active'
      else
        fail 'himmelblaud.service is not active'
      fi

      if check_tasks_active; then
        report PASS 'himmelblaud-tasks.service is active'
      else
        tasks_status=$?
        if [ "$tasks_status" -eq 2 ]; then
          report SKIP 'himmelblaud-tasks.service is not present'
        else
          fail 'himmelblaud-tasks.service exists but is not active'
        fi
      fi

      if [ -n "$upn" ]; then
        if check_nss_upn; then
          report PASS 'mapped Entra UPN resolves through NSS'
        else
          fail 'mapped Entra UPN does not resolve through NSS'
        fi
      else
        report SKIP 'no mapped UPN configured or supplied for NSS check'
      fi

      if check_aad_status; then
        report PASS 'aad-tool status succeeded'
      else
        fail 'aad-tool status failed'
      fi

      if check_broker_bus; then
        report PASS 'user D-Bus broker name is listable or activatable'
      else
        fail 'user D-Bus broker name is not reachable on this user bus'
      fi

      if check_sso_binary; then
        report PASS 'linux-entra-sso exists and --help exits cleanly'
      else
        fail 'linux-entra-sso is missing or --help failed'
      fi

      manifest_path=$(find_valid_firefox_manifest || true)
      if [ -n "$manifest_path" ]; then
        report PASS 'Firefox native messaging manifest points to an executable host'
      else
        fail 'Firefox native messaging manifest is missing or points to a non-executable host'
      fi

      [ "$failures" -eq 0 ]
    }
  '';
  entrablauSsoCheck = pkgs.writeShellApplication {
    name = "entrablau-sso-check";
    runtimeInputs = ssoRuntimeInputs;
    text = ssoDiagnosticsCommon + ''
      usage() {
        printf 'Usage: entrablau-sso-check [options]\n'
        usage_common
        printf '  --quiet             Only print failures\n'
      }

      silent=0
      parse_common_args "$@"
      if run_checks; then
        exit 0
      fi
      exit 1
    '';
  };
  entrablauSsoWait = pkgs.writeShellApplication {
    name = "entrablau-sso-wait";
    runtimeInputs = ssoRuntimeInputs;
    text = ssoDiagnosticsCommon + ''
      usage() {
        printf 'Usage: entrablau-sso-wait [options]\n'
        usage_common
        printf '  --timeout <sec>     Maximum wait time (default: 60)\n'
        printf '  --interval <sec>    Poll interval (default: 2)\n'
        printf '  --quiet             Suppress success output\n'
      }

      silent=0
      parse_common_args "$@"

      deadline=$(($(date +%s) + timeout))
      while true; do
        silent=1
        if run_checks; then
          silent=0
          if [ "$quiet" -eq 0 ]; then
            printf 'entrablau SSO prerequisites are ready\n'
          fi
          exit 0
        fi
        silent=0

        now=$(date +%s)
        if [ "$now" -ge "$deadline" ]; then
          printf 'FAIL entrablau SSO prerequisites were not ready after %ss\n' "$timeout" >&2
          run_checks || true
          exit 1
        fi
        sleep "$interval"
      done
    '';
  };
in

{
  config = lib.mkIf cfg.enable {
    services.himmelblau = {
      enable = true;

      daemonPackage = lib.mkForce himmelblauTpm.daemon;
      ssoPackage    = lib.mkForce himmelblauTpm.sso;
      brokerPackage = lib.mkForce himmelblauTpm.broker;
      pamPackage    = lib.mkForce himmelblauTpm.pam;
      nssPackage    = lib.mkForce himmelblauTpm.nss;

      # Auto-unseal cached Entra secrets at login (so the user's login
      # password unlocks the cached refresh-token / Hello PIN secrets).
      # DISABLED for now because the upstream himmelblau NixOS module
      # at rev b3c48849 has a typo: when tryUnsealFlag = true it
      # constructs a PAM rule referencing ''${cfg.package} which is
      # not a declared option (should be ''${cfg.pamPackage.lib}).
      # Module fails to eval. Track upstream:
      # nix/modules/himmelblau.nix:187 in himmelblau-idm/himmelblau.
      tryUnsealFlag = false;

      # Default list is [ "passwd" "login" "systemd-user" ]. sshd
      # gets force-added by the upstream module whenever
      # services.openssh.enable = true.
      pamServices = [ "passwd" "login" "systemd-user" ];

      settings = {
        # NB: upstream's module type is `listOf str`, not `str` --
        # a single-string would type-fail at eval.
        inherit (cfg) domain;

        enable_experimental_mfa = true;
        enable_experimental_passwordless_fido = true;

        apply_policy = true;

        # Hardware-attested keys via the TPM. Strict "tpm" mode:
        # fail loudly at enrollment if the TPM device is missing,
        # rather than silently soft-enrolling and getting rejected
        # by Intune later. Use "soft" if no TPM is available.
        hsm_type = "tpm";

        join_type = cfg.joinType;
        user_map_file = "/etc/himmelblau/user-map";

        # Keep mapped users in `wheel` so sudo still works after
        # Entra-backed login. Override at the consumer level if
        # this is not desired.
        local_groups = [ "wheel" ];

        # CN-based home dir layout. Enum values are lowercase
        # (uuid/spn/cn).
        home_attr = "cn";
        home_alias = "cn";
        use_etc_skel = true;

        # Disable short-name UPN-mapping (`alice` -> alice@<tenant>)
        # so NSS lookups for ordinary local accounts (useradd,
        # package install scripts) don't hit Entra and stall on
        # network.
        cn_name_mapping = false;
      };
    };

    environment.etc."himmelblau/user-map".text =
      lib.concatStringsSep "\n"
        (lib.mapAttrsToList (local: upn: "${local}:${upn}") cfg.userMap)
      + "\n";

    # Himmelblau/Entra NSS rows commonly carry /bin/bash as the
    # account shell. NixOS exposes bash through /run/current-system/sw/bin
    # by default, so keep the conventional path present and listed in
    # /etc/shells. Without this, himmelblaud can reject otherwise-valid
    # cached Entra accounts with "User shell is not present" and fall back
    # to interactive security-key authentication.
    environment.shells = [ "/bin/bash" ];
    systemd.tmpfiles.rules = [
      "L+ /bin/bash - - - - /run/current-system/sw/bin/bash"
    ];

    # himmelblaud runs with DynamicUser = yes (from upstream module).
    # /dev/tpmrm0 is mode 0660 owned by `tss` group (set by NixOS's
    # security.tpm2.enable udev rule). Grant supplementary group
    # membership so the dynamic user can open the TPM device.
    systemd.services.himmelblaud.serviceConfig.SupplementaryGroups = [ "tss" ];

    # Firefox needs to be installed via programs.firefox.enable (not
    # as a raw systemPackages entry) for the upstream Himmelblau
    # module's programs.firefox.policies.Extensions.Install setting
    # to take effect. The Himmelblau module auto-installs the
    # linux-entra-sso extension + native messaging host for browser
    # SSO.
    programs.firefox.enable = true;

    # Make Firefox the default browser for HTTP(S) -- it's the only
    # browser with linux-entra-sso wired in (the native-messaging
    # host can talk to himmelblaud to satisfy AAD auth requests
    # using the local PRT, no second Hello-PIN prompt). Anything
    # that fires xdg-open against an AAD consent URL thus lands in
    # the SSO-aware browser. `BROWSER=` is honoured by xdg-open
    # before the mime-type lookup, but we also bind the mime
    # defaults so KDE Plasma's "Open with" menu matches.
    environment.sessionVariables.BROWSER = "firefox";
    xdg.mime.defaultApplications = {
      "text/html"                 = "firefox.desktop";
      "application/xhtml+xml"     = "firefox.desktop";
      "x-scheme-handler/http"     = "firefox.desktop";
      "x-scheme-handler/https"    = "firefox.desktop";
      "x-scheme-handler/about"    = "firefox.desktop";
      "x-scheme-handler/unknown"  = "firefox.desktop";
    };

    # TPM-enabled aad-tool built locally so the user can run
    # `aad-tool tpm` / `aad-tool auth-test --name <upn>` from the
    # host shell.
    #
    # himmelblau's `himmelblau-sso` broker uses the `pinentry` Rust
    # crate (PinentryMessagePrinter, src/broker/src/main.rs) for the
    # interactive auth prompt (Hello PIN, password, FIDO2-touch).
    # The crate calls `with_default_binary()` which probes the
    # standard pinentry binary names on PATH; if none is found it
    # returns None and `prompt_echo_off()` immediately fails with
    # PAM_ABORT, without ever showing a UI to the user. That's the
    # symptom you see from sso-mib when it triggers interactive
    # auth:
    #   GDBus.Error:org.freedesktop.DBus.Error.Failed:
    #     Interactive authentication failed: PAM_ABORT
    #
    # Pinentry flavour:
    # - `pinentry-curses` / `pinentry-tty` need a controlling tty,
    #   which the D-Bus-session-activated broker doesn't have.
    # - `pinentry-gnome3` insists on GCR (the GNOME credential
    #   helper) and falls back to curses on KDE -- same problem.
    # - `pinentry-qt` is Qt-native, renders fine on Wayland, and
    #   matches the look of a Plasma desktop. `PINENTRY_BINARY`
    #   pins the selection.
    environment.systemPackages = [
      himmelblauTpm.aad-tool
      # Also expose the native-messaging host on the system profile so
      # readiness checks can verify the same binary Firefox invokes.
      himmelblauTpm.sso
      entrablauSsoCheck
      entrablauSsoWait
      pkgs.pinentry-qt
    ];
    environment.sessionVariables.PINENTRY_BINARY =
      "${pkgs.pinentry-qt}/bin/pinentry";
  };
}
