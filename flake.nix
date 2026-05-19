{
  description = "NixOS module for Microsoft Entra ID auth via Himmelblau (framework-agnostic)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      # The public surface area — populated by the refactor's Phase 3.
      #
      # `nixosModules.default` is reserved as an inert module from W0
      # onward so downstream consumers can pin the import path early
      # (`imports = [ inputs.nixos-entra-id.nixosModules.default ];`)
      # without "attribute missing" errors. Phase 3 replaces the
      # body with the actual Himmelblau + Intune-compliance wiring.
      #
      # nixosModules.default will eventually provide:
      #   nixosEntraId.{enable, domain, joinType, localUser, userMap}
      #   nixosEntraId.intuneCompliance.{fakeDmi, fakeOsRelease, …}
      # And bring along the Himmelblau workspace (PAM, NSS, broker,
      # daemon) plus a TPM-enabled rebuild of himmelblau.
      nixosModules.default = { lib, ... }: {
        config = lib.mkIf false { };
      };

      packages = forAllSystems (system: { });

      checks = forAllSystems (system: { });

      overlays.default = _final: _prev: { };
    };
}
