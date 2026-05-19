# Bare-metal example

A minimum NixOS host that uses `nixos-entra-id` on real hardware (no
microVM framework involved).

## Eval-test it

From this directory:

```bash
nix eval --no-write-lock-file \
  path:./.#nixosConfigurations.demo.config.system.build.toplevel.drvPath
```

That should print a `.drv` path, proving the module composes cleanly
without actually building anything.

## What's in here

`flake.nix` pins:

- `nixpkgs` — pinned independently of the parent flake so you can
  copy this directory and use it as a starting point.
- `nixos-entra-id` — pulled via `path:../..`, i.e. the parent repo.
  In a real consumer flake, swap this for
  `github:vicondoa/nixos-entra-id/v0.1.0`.

The module set:

- `nixos-entra-id.nixosModules.default` — imports the upstream
  Himmelblau NixOS module, our two concern files, and applies the
  `himmelblau-tpm` overlay.
- An inline module that declares the host's `nixosEntraId.*` shape:
  one tenant (`contoso.com`), one mapped user (`alice`), `join`
  type (Intune-enrolled), and a realistic-looking `fakeDmi` block.

## Bare-metal vs. VM

Nothing here knows about microVMs. To deploy the same module set
inside a [vicondoa/nixling] VM, see [`../inside-nixling-vm/`](../inside-nixling-vm/).

[vicondoa/nixling]: https://github.com/vicondoa/nixling
