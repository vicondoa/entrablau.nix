{
  description = "NixOS module for Microsoft Entra ID auth via Himmelblau (framework-agnostic)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Upstream Himmelblau workspace. Pinned to the same rev as
    # /etc/nixos's flake.lock at the time of the Phase-3 extract --
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
      #   imports = [ inputs.nixos-entra-id.nixosModules.default ];
      #   nixosEntraId.enable = true;
      #   nixosEntraId.domain = [ "contoso.com" ];
      #   nixosEntraId.userMap.alice = "alice@contoso.com";
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
          # don't actually build the system" so `nix flake check
          # --no-build` succeeds without realising a NixOS system.
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
          # mount / etc file when nixosEntraId.enable = false.
          disabled = mkSys [ { nixosEntraId.enable = false; } ];

          # Synthetic "intune-off" config -- Himmelblau is wired,
          # but the compliance shim must NOT be active. Asserts the
          # two halves of the module decompose cleanly.
          intuneOff = mkSys [
            {
              nixosEntraId = {
                enable = true;
                domain = [ "example.invalid" ];
                userMap.alice = "alice@example.invalid";
                joinType = "register";
                intuneCompliance.enable = false;
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
          # `nix flake check --no-build`, so the assertions go
          # here and `throw` synchronously during attrset eval.
          assertDisabled =
            if disabled.config.services.himmelblau.enable
            then throw "F1 eval-disabled: services.himmelblau.enable must be false when nixosEntraId.enable=false (the module is leaking config into the disabled branch)"
            else if disabled.config.environment.etc ? "himmelblau/fake-os-release"
            then throw "F1 eval-disabled: /etc/himmelblau/fake-os-release must NOT be defined when nixosEntraId.enable=false (the intune-compliance branch is firing unconditionally)"
            else null;

          assertIntuneOff =
            if !intuneOff.config.services.himmelblau.enable
            then throw "F1 eval-intune-off: services.himmelblau.enable must be true when nixosEntraId.enable=true (Himmelblau is the whole point)"
            else if intuneOff.config.environment.etc ? "himmelblau/fake-os-release"
            then throw "F1 eval-intune-off: /etc/himmelblau/fake-os-release must NOT be defined when intuneCompliance.enable=false (compliance shim leaking into the off branch)"
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
        in
        # eval-disabled is arch-agnostic: with nixosEntraId.enable=false the
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

