# Intune device-compliance shims for the Himmelblau workspace.
#
# These do not change what Himmelblau itself sees -- they change what
# the daemons report to Microsoft Intune during enrolment + ongoing
# compliance evaluation, so a NixOS host is not flagged as
# "unsupported distribution" and ejected from the tenant.
#
# Gated by `nixosEntraId.intuneCompliance.enable` (default true) so a
# pure Azure-AD-Registered BYOD host that is NOT enrolled in Intune
# can disable the shimming and run a vanilla Himmelblau workspace.
{ lib, config, ... }:

let
  cfg = config.nixosEntraId;
  compliance = cfg.intuneCompliance;
  dmiFields = lib.attrNames compliance.dmiOverride;
in

{
  config = lib.mkIf (cfg.enable && compliance.enable) {
    environment.etc = lib.mkMerge [
      {
        # Intune's compliance agent parses /etc/os-release to detect
        # the distribution; NixOS is not on the supported list.
        # Both /etc/os-release AND /usr/lib/os-release must be
        # overridden -- the Rust os_release crate reads /etc only
        # with no fallback, so bind-mounting just one leaves the
        # other reporting NixOS.  The content is taken from
        # `nixosEntraId.intuneCompliance.osReleaseOverride`.
        "himmelblau/os-release-override".text = compliance.osReleaseOverride;
      }

      # Per-key administrator-declared DMI files.  Each becomes
      # /etc/himmelblau/dmi-override/<k> with text = <v>\n.
      # Bind-mounted over /sys/class/dmi/id/<k> in the himmelblau
      # service namespaces only.
      (lib.mapAttrs'
        (k: v: lib.nameValuePair "himmelblau/dmi-override/${k}" { text = v + "\n"; })
        compliance.dmiOverride)
    ];

    # Apply the os-release + DMI bind-mounts to both the auth
    # daemon (sends DMI at enrollment) and the tasks daemon
    # (evaluates compliance rules against /etc/os-release).
    systemd.services.himmelblaud.serviceConfig.BindReadOnlyPaths = [
      "/etc/himmelblau/os-release-override:/etc/os-release"
      "/etc/himmelblau/os-release-override:/usr/lib/os-release"
    ] ++ (map (f: "/etc/himmelblau/dmi-override/${f}:/sys/class/dmi/id/${f}") dmiFields);

    systemd.services.himmelblaud-tasks.serviceConfig.BindReadOnlyPaths = [
      "/etc/himmelblau/os-release-override:/etc/os-release"
      "/etc/himmelblau/os-release-override:/usr/lib/os-release"
    ] ++ (map (f: "/etc/himmelblau/dmi-override/${f}:/sys/class/dmi/id/${f}") dmiFields);

    # The upstream tasks unit sets RestrictAddressFamilies=AF_UNIX,
    # which blocks ALL TCP/UDP sockets. apply_intune_policy runs
    # inside the tasks daemon and needs to reach Microsoft
    # endpoints (odc.officeapps.live.com, graph.microsoft.com).
    # With AF_UNIX-only, every reqwest call fails and the daemon
    # logs "Failed to apply Intune policies: federation provider
    # not set".
    systemd.services.himmelblaud-tasks.serviceConfig.RestrictAddressFamilies =
      lib.mkForce [ "AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK" ];

    # On clean shutdown himmelblaud calls export_broker_prts() and
    # tries to hand the sealed PRT blob to systemd's FileDescriptor-
    # Store. The upstream unit doesn't set FileDescriptorStoreMax so
    # the default (0) discards the FDs. On next start the in-memory
    # refresh_cache is empty, the Firefox SSO broker can't see the
    # device's PRT, and corporate sites lose SSO. Setting the store
    # to 1 lets the single exported blob survive restarts.
    systemd.services.himmelblaud.serviceConfig.FileDescriptorStoreMax = 1;

    # ProtectSystem=strict on the tasks unit makes /var read-only
    # except for ReadWritePaths. Upstream lists /var/cache/nss-
    # himmelblau but NOT /var/cache/himmelblau-policies (where
    # ScriptsCSE stages Intune scripts). /etc/cron.d is also
    # needed because ScriptsCSE writes one /etc/cron.d/policy_<id>
    # per Linux script policy. NixOS doesn't create /etc/cron.d
    # unless services.cron is on; tmpfiles below pre-creates them.
    systemd.services.himmelblaud-tasks.serviceConfig.ReadWritePaths = [
      "/var/cache/himmelblau-policies"
      "/etc/cron.d"
    ];

    systemd.tmpfiles.rules = [
      "d /etc/krb5.conf.d              0755 root root - -"
      "d /etc/cron.d                   0755 root root - -"
      "d /var/cache/himmelblau-policies 0700 root root - -"
    ];
  };
}
