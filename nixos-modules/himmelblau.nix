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
  cfg = config.nixosEntraId;
  himmelblauTpm = pkgs.himmelblauTpm;
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
    # `aad-tool tpm` / `aad-tool auth-test --name <local>` from the
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
      pkgs.pinentry-qt
    ];
    environment.sessionVariables.PINENTRY_BINARY =
      "${pkgs.pinentry-qt}/bin/pinentry";
  };
}
