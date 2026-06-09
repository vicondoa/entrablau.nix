# Bare-metal example

A minimum NixOS host that uses `entrablau.nix` (`github:vicondoa/entrablau.nix`)
on real hardware — no microVM framework involved.

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
- `entrablau` — pulled via `path:../..`, i.e. the parent repo.
  In a real consumer flake, swap this for
  `github:vicondoa/entrablau.nix/v1.0.0`.

The module set:

- `entrablau.nixosModules.default` — imports the upstream Himmelblau
  NixOS module, the two concern files, and applies the
  `himmelblau-tpm` overlay.
- `configuration.nix` — declares the host's `nixosEntraId.*` shape:
  one tenant (`contoso.com`), one mapped user (`alice`), `join` type
  (Intune-enrolled), and a `dmiOverride` block with administrator-
  declared DMI values.
