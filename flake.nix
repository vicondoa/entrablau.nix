{
  description = "NixOS module for Microsoft Entra ID auth via Himmelblau (framework-agnostic)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Upstream Himmelblau workspace. Pinned to the same rev as
    # /etc/nix/nix.conf's flake.lock at the time of the Phase-3 extract --
    # the sed patches in `pkgs/himmelblau-tpm/default.nix` anchor on
    # source lines that exist in this rev. The package has build-time
    # `grep` guards that fail loudly if a future upstream rev moves
    # those lines, so pinning is a stability choice, not a security
    # bound. Bump in coordination with the patch derivations -- see
    # `pkgs/himmelblau-tpm/MAINTAINING.md`.
    himmelblau = {
      url = "github:himmelblau-idm/himmelblau/b3c48849cc7b468e33b9e44bb1a1210e49e1391f";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, himmelblau, ... }@inputs:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      # The TPM-enabled Himmelblau rebuild is x86_64-only today --
      # `pkgs/himmelblau-tpm/` consumes the upstream Himmelblau flake's
      # pre-generated Cargo.nix which is only wired for x86_64-linux,
      # and the Intune CSR enrolment path was only verified on x86_64
      # hardware. Headless Himmelblau on aarch64 is a plausible
      # future extension; revisit when there's a real consumer.
      himmelblauSystems = [ "x86_64-linux" ];
      forHimmelblauSystems = nixpkgs.lib.genAttrs himmelblauSystems;

      # The overlay populates `pkgs.himmelblauTpm` with the TPM-
      # enabled rebuild of Himmelblau. Both the `nixosModules.default`
      # consumer-facing module AND the `packages.<sys>.*` outputs
      # below use it, so it's hoisted to a let binding.
      #
      # Uses `final.callPackage` (not raw `import`) so downstream
      # overlay composition can override the package the standard
      # way (`overrideAttrs`, `overrideArgs`, `.override { ... }`).
      # `himmelblauSrc` is threaded through as a non-pkgs arg.
      himmelblauTpmOverlay = final: _prev: {
        himmelblauTpm = final.callPackage ./pkgs/himmelblau-tpm {
          himmelblauSrc = himmelblau;
        };
      };

      pkgsFor = system: import nixpkgs {
        inherit system;
        overlays = [ himmelblauTpmOverlay ];
      };
    in
    {
      # Consumer entry point. A consumer flake does:
      #
      #   imports = [ inputs.entrablau.nixosModules.default ];
      #   entrablau.enable = true;
      #   entrablau.domain = [ "contoso.com" ];
      #   entrablau.userMap.alice = "alice@contoso.com";
      #
      # The wrapper here imports the upstream Himmelblau NixOS module
      # (from our pinned `inputs.himmelblau`) AND applies the
      # himmelblau-tpm overlay so `pkgs.himmelblauTpm` is available to
      # the consumed modules. The actual option schema + config logic
      # lives under `./nixos-modules`.
      nixosModules.default = { lib, ... }: {
        imports = [
          himmelblau.nixosModules.himmelblau
          ./nixos-modules
        ];
        nixpkgs.overlays = [ himmelblauTpmOverlay ];
      };

      overlays.default = himmelblauTpmOverlay;

      # Diagnostics + composability. `nix build .#himmelblau-tpm`
      # produces the TPM-enabled aad-tool binary (the most useful
      # standalone diagnostic -- `aad-tool tpm` reports real TPM
      # state, `aad-tool auth-test` exercises end-to-end auth).
      # Sub-binaries are exposed separately for completeness.
      #
      # Restricted to x86_64-linux: see `himmelblauSystems` above.
      packages = forHimmelblauSystems (system:
        let pkgs = pkgsFor system; in {
          himmelblau-tpm        = pkgs.himmelblauTpm.aad-tool;
          himmelblau-tpm-daemon = pkgs.himmelblauTpm.daemon;
          himmelblau-tpm-broker = pkgs.himmelblauTpm.broker;
          himmelblau-tpm-sso    = pkgs.himmelblauTpm.sso;
          himmelblau-tpm-pam    = pkgs.himmelblauTpm.pam;
          himmelblau-tpm-nss    = pkgs.himmelblauTpm.nss;
        });

      checks = forAllSystems (system:
        let
          pkgs = pkgsFor system;

          # Helper: build a NixOS configuration with our module and
          # a placeholder host config. The `bootstrap` overlay
          # provides just enough to keep nixosSystem from refusing
          # to evaluate without hardware / filesystem context.
          bootstrap = { lib, ... }: {
            boot.loader.grub.enable = false;
            boot.loader.systemd-boot.enable = lib.mkDefault true;
            boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
            fileSystems."/" = {
              device = "/dev/disk/by-label/nixos";
              fsType = "ext4";
            };
            networking.hostName = "check";
            system.stateVersion = "25.11";
            users.users.alice = {
              isNormalUser = true;
              uid = 1000;
              extraGroups = [ "wheel" ];
            };
            security.tpm2.enable = lib.mkDefault true;
          };

          mkSys = extraModules: nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              bootstrap
            ] ++ extraModules;
          };

          # Wrap a fully-evaluated nixosSystem in a buildable check
          # marker. Referencing `config.system.build.toplevel.drvPath`
          # forces the whole module system to evaluate to a derivation
          # path; if anything is wrong upstream (a missing option, a
          # type mismatch, an assertion failure) the .drvPath access
          # throws and the check fails. We strip the string context
          # via `unsafeDiscardStringContext` so the toplevel drv is
          # not pulled as a build input -- the goal is "eval-only,
          # don't actually build the system" so these checks avoid
          # realising full NixOS system closures.
          mkEvalCheck = name: config: pkgs.runCommand name {
            preferLocalBuild = true;
            allowSubstitutes = false;
            drvPath = builtins.unsafeDiscardStringContext
              config.system.build.toplevel.drvPath;
          } ''
            mkdir -p $out
            printf '%s\n' "$drvPath" > $out/drv-path
          '';

          # Synthetic "disabled" config -- the module must be a
          # complete no-op for every consumer-visible service /
          # mount / etc file when entrablau.enable = false.
          disabled = mkSys [ { entrablau.enable = false; } ];

          # Synthetic "intune-off" config -- Himmelblau is wired,
          # but the compliance shim must NOT be active. Asserts the
          # two halves of the module decompose cleanly.
          intuneOff = mkSys [
            {
              entrablau = {
                enable = true;
                domain = [ "example.invalid" ];
                userMap.alice = "alice@example.invalid";
                joinType = "register";
                intuneCompliance.enable = false;
              };
            }
          ];

          # Synthetic "intune-on" config -- compliance shim active with
          # a minimal dmiOverride block AND an explicit osReleaseOverride
          # value.  The sentinel string "ID=entrablau-eval-sentinel" is
          # distinctive enough that any drift in the option type (e.g.
          # lines → attrsOf) that corrupts text rendering will be caught
          # by assertIntuneOn below.
          intuneOn = mkSys [
            {
              entrablau = {
                enable = true;
                domain = [ "example.invalid" ];
                userMap.alice = "alice@example.invalid";
                joinType = "join";
                intuneCompliance = {
                  enable = true;
                  dmiOverride = {
                    sys_vendor   = "Example Corp.";
                    product_name = "ExampleBook 1";
                  };
                  osReleaseOverride = ''
                    ID=entrablau-eval-sentinel
                    NAME="Entrablau Eval Sentinel OS"
                    PRETTY_NAME="Entrablau Eval Sentinel OS 22.04"
                    VERSION_ID="22.04"
                    VERSION_CODENAME=entrablau_eval
                  '';
                };
              };
            }
          ];

          # The bare-metal example (examples/bare-metal-host/). We
          # reuse the same configuration.nix that the example flake
          # imports, so any future drift between "what the example
          # shows" and "what this flake supports" trips this check.
          bareMetal = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              self.nixosModules.default
              ./examples/bare-metal-host/configuration.nix
            ];
          };

          # F1 evaluation-time assertions. These are not module
          # asserts -- a module assertion fires only when the
          # toplevel is built. We want errors visible at
          # flake evaluation, so the assertions go here and `throw`
          # synchronously during attrset eval.
          assertDisabled =
            if disabled.config.services.himmelblau.enable
            then throw "F1 eval-disabled: services.himmelblau.enable must be false when entrablau.enable=false (the module is leaking config into the disabled branch)"
            else if disabled.config.environment.etc ? "himmelblau/os-release-override"
            then throw "F1 eval-disabled: /etc/himmelblau/os-release-override must NOT be defined when entrablau.enable=false (the intune-compliance branch is firing unconditionally)"
            else if disabled.config.environment.etc ? "himmelblau/fake-os-release"
            then throw "F1 eval-disabled: old path himmelblau/fake-os-release must not appear in evaluated config"
            else null;

          assertIntuneOff =
            let
              systemPackageNames =
                map (pkg: nixpkgs.lib.getName pkg)
                  intuneOff.config.environment.systemPackages;
            in
            if !intuneOff.config.services.himmelblau.enable
            then throw "F1 eval-intune-off: services.himmelblau.enable must be true when entrablau.enable=true (Himmelblau is the whole point)"
            else if !(nixpkgs.lib.elem "/bin/bash" intuneOff.config.environment.shells)
            then throw "F1 eval-intune-off: /bin/bash must be listed in environment.shells for Entra NSS shell compatibility"
            else if !(nixpkgs.lib.elem "L+ /bin/bash - - - - /run/current-system/sw/bin/bash" intuneOff.config.systemd.tmpfiles.rules)
            then throw "F1 eval-intune-off: /bin/bash tmpfiles symlink must be installed for Entra NSS shell compatibility"
            else if !(nixpkgs.lib.elem "entrablau-sso-check" systemPackageNames)
            then throw "F1 eval-intune-off: entrablau-sso-check must be installed when entrablau.enable=true"
            else if !(nixpkgs.lib.elem "entrablau-sso-wait" systemPackageNames)
            then throw "F1 eval-intune-off: entrablau-sso-wait must be installed when entrablau.enable=true"
            else if intuneOff.config.environment.etc ? "himmelblau/os-release-override"
            then throw "F1 eval-intune-off: /etc/himmelblau/os-release-override must NOT be defined when intuneCompliance.enable=false (compliance shim leaking into the off branch)"
            else if intuneOff.config.environment.etc ? "himmelblau/fake-os-release"
            then throw "F1 eval-intune-off: old path himmelblau/fake-os-release must not appear in evaluated config"
            # The widening of RestrictAddressFamilies is a compliance-shim
            # behaviour and must also be off. The upstream module sets it
            # to the string "AF_UNIX"; our shim mkForce-overrides to a
            # 4-element list. Asserting strict equality with the upstream
            # value catches any future shim that forgets to gate on
            # `compliance.enable`.
            else if intuneOff.config.systemd.services.himmelblaud-tasks.serviceConfig.RestrictAddressFamilies != "AF_UNIX"
            then throw "F1 eval-intune-off: RestrictAddressFamilies widening must NOT apply when intuneCompliance.enable=false (expected upstream's \"AF_UNIX\" string, got something else)"
            # FileDescriptorStoreMax=1 is part of the compliance shim
            # (PRT survival across restarts). Off branch must not set it.
            else if (intuneOff.config.systemd.services.himmelblaud.serviceConfig.FileDescriptorStoreMax or null) != null
            then throw "F1 eval-intune-off: FileDescriptorStoreMax must NOT be set when intuneCompliance.enable=false"
            else null;

          assertIntuneOn =
            let
              etcCfg  = intuneOn.config.environment.etc;
              svcAuth = intuneOn.config.systemd.services.himmelblaud.serviceConfig;
              svcTask = intuneOn.config.systemd.services.himmelblaud-tasks.serviceConfig;
              authBinds = svcAuth.BindReadOnlyPaths or [];
              taskBinds = svcTask.BindReadOnlyPaths or [];
              hasOsRelease = s: nixpkgs.lib.any (b: nixpkgs.lib.hasPrefix "/etc/himmelblau/os-release-override:" b) s;
              hasDmiOverride = s: nixpkgs.lib.any (b: nixpkgs.lib.hasInfix "dmi-override" b) s;
              # Sentinel string set in the intuneOn config above.  Any
              # type-shape drift (e.g. lines → attrsOf) that corrupts
              # text serialisation will make the .text field not contain
              # this value and the check below will catch it.
              osReleaseSentinel = "ID=entrablau-eval-sentinel";
              osReleaseText = etcCfg."himmelblau/os-release-override".text or "";
              # Exact bind-mount entries the compliance module must emit.
              hasEtcOsRelease = s:
                nixpkgs.lib.elem "/etc/himmelblau/os-release-override:/etc/os-release" s;
              hasUsrLibOsRelease = s:
                nixpkgs.lib.elem "/etc/himmelblau/os-release-override:/usr/lib/os-release" s;
            in
            if !(etcCfg ? "himmelblau/os-release-override")
            then throw "F1 eval-intune-on: /etc/himmelblau/os-release-override must be defined when intuneCompliance.enable=true"
            else if etcCfg ? "himmelblau/fake-os-release"
            then throw "F1 eval-intune-on: old path himmelblau/fake-os-release must not appear in evaluated config"
            else if !(nixpkgs.lib.hasInfix osReleaseSentinel osReleaseText)
            then throw "F1 eval-intune-on: /etc/himmelblau/os-release-override .text must contain the sentinel '${osReleaseSentinel}' -- type-shape drift in osReleaseOverride option?"
            else if !(hasOsRelease authBinds)
            then throw "F1 eval-intune-on: himmelblaud BindReadOnlyPaths must include os-release-override bind mount"
            else if !(hasOsRelease taskBinds)
            then throw "F1 eval-intune-on: himmelblaud-tasks BindReadOnlyPaths must include os-release-override bind mount"
            else if !(hasEtcOsRelease authBinds)
            then throw "F1 eval-intune-on: himmelblaud BindReadOnlyPaths must include os-release-override:/etc/os-release"
            else if !(hasEtcOsRelease taskBinds)
            then throw "F1 eval-intune-on: himmelblaud-tasks BindReadOnlyPaths must include os-release-override:/etc/os-release"
            else if !(hasUsrLibOsRelease authBinds)
            then throw "F1 eval-intune-on: himmelblaud BindReadOnlyPaths must include os-release-override:/usr/lib/os-release"
            else if !(hasUsrLibOsRelease taskBinds)
            then throw "F1 eval-intune-on: himmelblaud-tasks BindReadOnlyPaths must include os-release-override:/usr/lib/os-release"
            else if !(hasDmiOverride authBinds)
            then throw "F1 eval-intune-on: himmelblaud BindReadOnlyPaths must include dmi-override bind mounts"
            else if !(hasDmiOverride taskBinds)
            then throw "F1 eval-intune-on: himmelblaud-tasks BindReadOnlyPaths must include dmi-override bind mounts"
            else null;
        in
        # eval-disabled is arch-agnostic: with entrablau.enable=false the
        # module is fully inert and pkgs.himmelblauTpm is never referenced,
        # so it works on aarch64 too.
        {
          eval-disabled = builtins.seq assertDisabled
            (mkEvalCheck "eval-disabled" disabled.config);
        }
        # The rest reference pkgs.himmelblauTpm (which is gated to
        # x86_64-linux upstream), so we only expose them on
        # himmelblauSystems.
        // (nixpkgs.lib.optionalAttrs (builtins.elem system himmelblauSystems) {
          eval-intune-off = builtins.seq assertIntuneOff
            (mkEvalCheck "eval-intune-off" intuneOff.config);

          eval-intune-on = builtins.seq assertIntuneOn
            (mkEvalCheck "eval-intune-on" intuneOn.config);

          eval-bare-metal = mkEvalCheck "eval-bare-metal" bareMetal.config;

          # Derivation-evaluation check for the TPM-enabled aad-tool
          # rebuild. Surfaces upstream Cargo.nix / crate-override
          # eval breakage without paying for a ~10-minute Rust
          # compile every CI run.
          himmelblau-tpm-drv = pkgs.runCommand "himmelblau-tpm-drv" {
            preferLocalBuild = true;
            allowSubstitutes = false;
            drvPath = builtins.unsafeDiscardStringContext
              pkgs.himmelblauTpm.aad-tool.drvPath;
          } ''
            mkdir -p $out
            printf '%s\n' "$drvPath" > $out/drv-path
          '';
        }));
    };
}
