# Rebuild Himmelblau with the `tpm` cargo feature actually wired through
# to every workspace binary, so `aad-tool tpm` reports real TPM state
# instead of "Hardware TPM supported was not enabled in this build".
#
# Why this exists:
#   - github:himmelblau-idm/himmelblau (main, rev b3c48849 at time of
#     writing) generates its Cargo.nix WITHOUT propagating the `tpm`
#     cargo feature to the workspace binaries (aad-tool / daemon / pam
#     / broker / nss). Their Cargo.toml files declare deps as
#     `himmelblau_unix_common.workspace = true` without
#     `features = ["tpm"]`, so the deps are compiled minus TPM support.
#   - The result: even with a fully functional /dev/tpmrm0 in the VM
#     (verified via tpm2_getrandom etc.), aad-tool returns
#     "Hardware TPM supported was not enabled in this build."
#   - This module patches the upstream Cargo.nix at Nix-build-time to
#     add features=["tpm"] to the right dep entries, then injects two
#     crateOverrides (tss-esapi-sys + tss-esapi) so the TPM crates can
#     find libtss2 + libclang and don't panic on missing
#     DEP_TSS2_ESYS_VERSION (crate2nix doesn't honor Cargo's `links`
#     mechanism that normally sets that env var downstream).
#
# Important quoting note:
#   The crateOverride text injected into default.nix MUST keep
#   ${pkgs.llvmPackages.libclang.lib} etc. as UNEVALUATED Nix
#   expressions (evaluated at the patched-default.nix import time).
#   If we pre-substitute them to literal /nix/store paths at this
#   outer module's eval time, the resulting strings have no Nix
#   string context — clang/glibc/tpm2-tss don't get added as
#   build inputs of tss-esapi-sys, and the sandbox blocks access:
#   bindgen panics with "Unable to find libclang ... (invalid: [])".
#   So we escape `$` as ''$ inside the outer Nix string so the
#   literal `${pkgs.X}` text lands in default.nix verbatim.
{ pkgs, himmelblauSrc, ... }:

let
  # Vendored libhimmelblau 0.8.18 .crate (from crates.io), unpacked and
  # patched to send the Intune device-enrolment CSR as PEM-wrapped base64
  # instead of raw base64 of DER.
  #
  # Upstream bug (libhimmelblau/src/intune.rs line 521):
  #   "CertificateSigningRequest": STANDARD.encode(csr_der),
  #
  # Microsoft's Intune endpoint for strict Conditional-Access tenants
  # enforces "PEM-encoded PKCS#10":
  #   400 Bad Request: Value must be a valid PEM-encoded PKCS#10 CSR
  #   with an RSA key of at least 2048 bits.
  #
  # The key IS RSA-2048 (verified: kanidm-hsm-crypto's TssTpm.rs256_create
  # uses RsaKeyBits::Rsa2048; SoftTpm uses rsa::MIN_BITS = 2048). So the
  # rejection is the format: raw-base64-of-DER vs PEM with -----BEGIN
  # CERTIFICATE REQUEST----- headers.
  #
  # Microsoft's own Linux Intune client sends real PEM, and tolerant Intune
  # backends accept either; strict corporate tenants do not. Wrap it.
  libhimmelblauCrate = pkgs.fetchurl {
    url = "https://crates.io/api/v1/crates/libhimmelblau/0.8.18/download";
    name = "libhimmelblau-0.8.18.crate";
    sha256 = "07nd2ffb3lh9v1j2hwx5vj92q5l1wmiv8qx0q6a7dxzf80dc1g2z";
  };

  # Vendored kanidm-hsm-crypto 0.3.6 .crate (from crates.io), unpacked and
  # patched so the TPM-generated PKCS#10 CSR carries the X.509v3 extensions
  # Microsoft Intune's Linux enrollment endpoint actually requires:
  #
  #   X509v3 Key Usage:          critical, digitalSignature, keyEncipherment
  #   X509v3 Extended Key Usage: TLS Web Client Authentication (clientAuth)
  #
  # Upstream src/provider/mod.rs::ms_device_enrolment_begin() builds the CSR
  # via crypto_glue::x509::CertificateRequestBuilder::new() and immediately
  # calls .finalize() WITHOUT adding any extensions. The resulting CSR has
  # an empty `Extension Request` PKCS#9 attribute and Intune rejects it with
  # the misleading error: "Value must be a valid PEM-encoded PKCS#10 CSR
  # with an RSA key of at least 2048 bits." (the key IS RSA-2048; the real
  # complaint is the missing extensions).
  #
  # Verified against MS Intune endpoint by replaying captured payloads with
  # curl: identical CSR + extensions = HTTP 200 + valid device cert from
  # "Microsoft Intune Beta MDM Device CA"; without the extensions = HTTP 400.
  kanidmHsmCryptoCrate = pkgs.fetchurl {
    url = "https://crates.io/api/v1/crates/kanidm-hsm-crypto/0.3.6/download";
    name = "kanidm-hsm-crypto-0.3.6.crate";
    sha256 = "1ya3xqvpsy83hq65l2syzgfd3mdacsinyndgnkxymmvyl4zc9fdz";
  };

  kanidmHsmCryptoPatched = pkgs.runCommand "kanidm-hsm-crypto-0.3.6-csr-ext" { } ''
    mkdir -p $out
    ${pkgs.gnutar}/bin/tar -xzf ${kanidmHsmCryptoCrate} -C $out --strip-components=1
    chmod -R u+w $out

    # 1. Extend the crypto_glue::x509 import line to bring KeyUsage,
    #    KeyUsages (the FlagSet enum), ExtendedKeyUsage and the const_oid
    #    db re-export `oiddb` into scope. All four are already re-exported
    #    by crypto-glue 0.1.13's x509/mod.rs, so no extra Cargo.toml
    #    changes are needed — only the Rust source `use` line.
    ${pkgs.gnused}/bin/sed -i -E \
      's@^    self, BitString, Builder, Certificate, CertificateRequest, CertificateRequestBuilder,$@&\n    ExtendedKeyUsage, KeyUsage, KeyUsages, oiddb,@' \
      $out/src/provider/mod.rs

    # 2. Inject the two add_extension() calls between
    #      let mut req_builder = CertificateRequestBuilder::new(...)?;
    #    and
    #      let csr_to_sign = req_builder.finalize()?;
    #    so the extensions land in self.extension_req BEFORE finalize()
    #    serialises it as the PKCS#9 ExtensionRequest attribute (see
    #    x509-cert 0.2.5 src/builder.rs::finalize for RequestBuilder).
    #
    #    `KeyUsage` impl_extension!s with critical=true (per RFC 5280).
    #    `ExtendedKeyUsage` is non-critical, which matches what MS expects
    #    (verified empirically — only KeyUsage MUST be critical).
    #
    #    Sed delimiter is `@` because the replacement contains `|` (BitOr
    #    on KeyUsages flags) and `/` (none here, but defensive). `\&`
    #    escapes ampersand-as-match. `\n` in the replacement is GNU sed's
    #    newline. We anchor on the unique `let csr_to_sign = req_builder`
    #    line to insert BEFORE it.
    ${pkgs.gnused}/bin/sed -i -E \
      's@^        let csr_to_sign = req_builder$@        req_builder.add_extension(\&KeyUsage(KeyUsages::DigitalSignature | KeyUsages::KeyEncipherment)).map_err(|_| TpmError::X509RequestBuilder)?;\n        req_builder.add_extension(\&ExtendedKeyUsage(vec![oiddb::rfc5280::ID_KP_CLIENT_AUTH])).map_err(|_| TpmError::X509RequestBuilder)?;\n        let csr_to_sign = req_builder@' \
      $out/src/provider/mod.rs

    # Verify both patches landed (else fail loudly here, not at runtime).
    if ! ${pkgs.gnugrep}/bin/grep -q 'KeyUsages::DigitalSignature | KeyUsages::KeyEncipherment' $out/src/provider/mod.rs; then
      echo "ERROR: kanidm-hsm-crypto KeyUsage patch did not apply"
      exit 1
    fi
    if ! ${pkgs.gnugrep}/bin/grep -q 'ID_KP_CLIENT_AUTH' $out/src/provider/mod.rs; then
      echo "ERROR: kanidm-hsm-crypto ExtendedKeyUsage patch did not apply"
      exit 1
    fi
    if ! ${pkgs.gnugrep}/bin/grep -q '    ExtendedKeyUsage, KeyUsage, KeyUsages, oiddb,' $out/src/provider/mod.rs; then
      echo "ERROR: kanidm-hsm-crypto import patch did not apply"
      exit 1
    fi
  '';

  libhimmelblauPatched = pkgs.runCommand "libhimmelblau-0.8.18-pem-csr" { } ''
    mkdir -p $out
    ${pkgs.gnutar}/bin/tar -xzf ${libhimmelblauCrate} -C $out --strip-components=1
    chmod -R u+w $out
    # Replace raw base64 with PEM-wrapped CSR. RFC 7468 §2 / §3 requires
    # base64 lines of AT MOST 64 chars; Microsoft Intune's parser is strict
    # about this — a single-line base64 between BEGIN/END markers gets
    # rejected with the same generic "must be PEM-encoded" error.
    #
    # We chunk the base64 into 64-char lines via .as_bytes().chunks(64).
    # The `std::str::from_utf8(c).unwrap_or("")` is safe because base64
    # chars are all ASCII so every 64-byte chunk is a valid str.
    #
    # Compute csr_pem after the csr_der binding so it's in-scope for the
    # json! macro, then replace ONLY the first occurrence of the raw
    # base64 in the CertificateSigningRequest field (line 522 ish, in
    # enroll()) — the other "let payload = json!({" near line 593
    # doesn't reference csr_der at all.
    ${pkgs.gnused}/bin/sed -i -E \
      -e 's@(\.map_err\(\|e\| MsalError::CryptoFail\(format!\("Failed creating CSR: \{:\?\}", e\)\)\)\?;)@\1\n        let csr_pem: String = { let b64 = STANDARD.encode(\&csr_der); let body: String = b64.as_bytes().chunks(64).map(|c| std::str::from_utf8(c).unwrap_or("")).collect::<Vec<_>>().join("\\n"); format!("-----BEGIN CERTIFICATE REQUEST-----\\n{}\\n-----END CERTIFICATE REQUEST-----\\n", body) };@' \
      -e '0,/"CertificateSigningRequest": STANDARD\.encode\(csr_der\),/{s@"CertificateSigningRequest": STANDARD\.encode\(csr_der\),@"CertificateSigningRequest": csr_pem,@}' \
      $out/src/intune.rs
    # Verify the changes landed (else build fails loudly here, not deep
    # in the daemon at runtime).
    if ! ${pkgs.gnugrep}/bin/grep -q 'BEGIN CERTIFICATE REQUEST' $out/src/intune.rs; then
      echo "ERROR: libhimmelblau PEM patch did not apply"
      exit 1
    fi
    if ! ${pkgs.gnugrep}/bin/grep -q 'chunks(64)' $out/src/intune.rs; then
      echo "ERROR: libhimmelblau PEM chunking patch did not apply"
      exit 1
    fi
  '';

  patchedSrc = pkgs.runCommand "himmelblau-tpm-source" { } ''
    cp -r ${himmelblauSrc} $out
    chmod -R u+w $out
    cd $out

    # Let the generated default.nix receive our patched crate sources as
    # normal Nix arguments. This avoids embedding absolute /nix/store paths
    # in generated source, which pure flake evaluation rejects on fresh
    # machines.
    ${pkgs.gnused}/bin/sed -i '1a\
  libhimmelblauPatched,\
  kanidmHsmCryptoPatched,
    ' default.nix

    # 1. Cargo.nix: enable `tpm` cargo feature on the relevant dep
    #    entries inside every workspace member's dependencies block.
    #    The pattern matches bare {name; packageId;} blocks that lack
    #    a features list — these appear in MULTIPLE workspace
    #    binaries (aad-tool, daemon, pam, broker, nss), so a single
    #    global s/// covers all of them.
    ${pkgs.gnused}/bin/sed -z -i -E '
      s|(\{\s*\n\s*name = "himmelblau_unix_common";\s*\n\s*packageId = "himmelblau_unix_common";)\s*\n(\s*\})|\1\n            features = [ "tpm" ];\n\2|g
      s|(\{\s*\n\s*name = "kanidm-hsm-crypto";\s*\n\s*packageId = "kanidm-hsm-crypto";)\s*\n(\s*\})|\1\n            features = [ "tpm" ];\n\2|g
    ' Cargo.nix
    # libhimmelblau has an existing features list; append "tpm" to it.
    ${pkgs.gnused}/bin/sed -i 's/\("set_timeout" \)\(\]\)/\1"tpm" \2/g' Cargo.nix

    # 2. default.nix: inject crateOverrides for the new TPM-linking
    #    crates AND for libhimmelblau (point its src at our PEM-patched
    #    vendored copy). The escapes keep references to pkgs attributes
    #    as unevaluated Nix expressions in the OUTPUT default.nix (so
    #    Nix's string context properly registers clang/glibc/tpm2-tss
    #    as build inputs of these overrides — without that, the
    #    sandbox blocks their access).
    ${pkgs.gnused}/bin/sed -i -E '
      /defaultCrateOverrides = pkgs.defaultCrateOverrides \/\/ \{/ a\
          tss-esapi-sys = attrs: {\
            nativeBuildInputs = [ pkgs.pkg-config ];\
            buildInputs = [ pkgs.tpm2-tss ];\
            LIBCLANG_PATH = "''${pkgs.llvmPackages.libclang.lib}/lib";\
            BINDGEN_EXTRA_CLANG_ARGS = pkgs.lib.concatStringsSep " " [\
              "-isystem ''${pkgs.llvmPackages.libclang.lib}/lib/clang/''${pkgs.llvmPackages.libclang.version}/include"\
              "-isystem ''${pkgs.glibc.dev}/include"\
              "-isystem ''${pkgs.tpm2-tss.dev}/include"\
            ];\
          };\
          tss-esapi = attrs: {\
            nativeBuildInputs = [ pkgs.pkg-config ];\
            buildInputs = [ pkgs.tpm2-tss ];\
            DEP_TSS2_ESYS_VERSION = "''${pkgs.tpm2-tss.version}";\
          };\
          libhimmelblau = attrs: {\
            src = libhimmelblauPatched;\
          };\
          kanidm-hsm-crypto = attrs: {\
            src = kanidmHsmCryptoPatched;\
          };
    ' default.nix
  '';

  # The upstream crate2nix-generated derivations don't set `meta.license`
  # in a way that survives our crateOverride machinery, so stamp it
  # explicitly on each workspace binary we expose. These outputs are a
  # combined work of:
  #   - Himmelblau (GPL-3.0-or-later, dominant)
  #   - libhimmelblau (LGPL-3.0-or-later, statically linked)
  #   - kanidm-hsm-crypto (MPL-2.0, statically linked)
  # The combined-work license is GPL-3.0-or-later. See ../../THIRD-PARTY.md.
  rawPackages = (import patchedSrc {
    inherit pkgs libhimmelblauPatched kanidmHsmCryptoPatched;
  }).packages;
in
pkgs.lib.mapAttrs
  (_name: drv: drv.overrideAttrs (old: {
    meta = (old.meta or { }) // {
      license = pkgs.lib.licenses.gpl3Plus;
      homepage = "https://github.com/himmelblau-idm/himmelblau";
    };
  }))
  rawPackages
