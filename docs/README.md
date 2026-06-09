# entrablau.nix documentation

Welcome to the `entrablau.nix` documentation. This flake provides a
framework-agnostic NixOS module for joining a NixOS host to Microsoft
Entra ID via Himmelblau, with optional Intune compliance shimming.

## Contents

| Document | Description |
|---|---|
| [How-to: Import into NixOS](./how-to/import-into-nixos.md) | Step-by-step guide for adding the module to a NixOS configuration |
| [Reference: Options](./reference/options.md) | Full `entrablau.*` option reference and v0.1.0 → v1.0.0 migration table |
| [Reference: GitHub Actions](./reference/github-actions.md) | CI workflow design and security posture |
| [Explanation: Design](./explanation/design.md) | Architecture rationale and key design decisions |

## Getting started quickly

See the top-level [`README.md`](../README.md) for a minimal quick
start (add input, configure, rebuild, enrol).

## Option root

All options live under `entrablau.*`. The namespace is stable from
v1.0.0; no compatibility aliases exist for pre-1.0 option paths.
