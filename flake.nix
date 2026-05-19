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

      checks = forAllSystems (_system: { });
    };
}

