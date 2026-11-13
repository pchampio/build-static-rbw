# build-static-rbw

Build the latest **[rylos/rbw enhanced branch](https://github.com/rylos/rbw/tree/enhanced)** as static Linux amd64 and arm64 binaries. Each archive contains `rbw` and `rbw-agent`, with the default TUI and clipboard features, upstream MIT license, upstream Cargo.lock, applied build patches, and BUILD-INFO.txt.

## Build a release

In Actions, select **Build latest enhanced rbw → Run workflow**. Or:

```sh
gh workflow run build.yml --repo pchampio/build-static-rbw
```

Pushing to main also builds a release. There is no timer. Every run resolves the current enhanced branch once and uses the same full commit on both architectures. This does not follow upstream release tags. Tests and static ELF checks must pass on both architectures before publication. Each run publishes a unique release and marks it latest; previous releases remain available for rollback. Re-running the same source still creates a new release.

One small [build patch](patches/0001-unlock-before-free.patch) releases the memory-lock guard before freeing its backing allocation. Without it, the fork's attachment encryption test panics under musl on both architectures. The build verifies patch applicability, applies it explicitly, and records/bundles its hash. Future upstream changes that conflict with the patch fail the build rather than silently omitting it. No tests are skipped.

The build uses current stable Rust and `cargo --locked`: upstream dependency versions are preserved. Each release includes source and builder commits, compiler versions, lockfile hash, SHA256SUMS, and a fresh OSV dependency advisory report. Checksums detect corruption; they are not independent signatures or a security guarantee. The report covers the entire lockfile, including optional/platform dependencies, without establishing reachability. **Advisory matches are visible but do not block publication.** A failed OSV request does block publication, so a release cannot silently omit its report.

## Security status

**This is a packaging repository, not a security endorsement. Known dependency advisories were present during the initial review. An unconditional migration is not recommended until these are resolved or assessed.** Read [SECURITY-REVIEW.md](SECURITY-REVIEW.md) and each release's dependency-report.md before installing. Automatically following latest git means future source is unreviewed; the initial review does not certify future builds.

Source/dependency code runs in jobs with read-only repository permissions, no repository checkout credentials, and no vault credentials. A separate job publishes artifacts with contents-write permission, without executing upstream binaries. Actions are pinned by commit; Dependabot proposes updates. No upstream contrib scripts, polkit/PAM configuration, remembered passwords, PIN, or auto-unlock are installed or enabled by this repository.

## Download

```sh
mkdir rbw-download && cd rbw-download
gh release download --repo pchampio/build-static-rbw --pattern 'rbw-enhanced-linux-amd64.tar.gz' --pattern SHA256SUMS
# Verify the selected archive against the release checksum manifest.
grep ' ./rbw-enhanced-linux-amd64.tar.gz$' SHA256SUMS | sha256sum -c -
tar xzf rbw-enhanced-linux-amd64.tar.gz
```

Use arm64 instead of amd64 when appropriate. Pinentry remains an external runtime requirement. Desktop clipboard integration can require desktop libraries/services available on the host; static ELF checks cover linked libraries, not dynamically loaded integrations. System authentication, typing tools and Secret Service integrations also require their respective host tools. Existing rbw configuration/profile paths are reused. Restart the old agent before using the new client; back up your encrypted local cache/config first if you need rollback.

The dotfiles installer selects the amd64 archive, matching its existing Linux amd64 installation convention. This repository does not run that installer or access your vault.

## Local build

On native Linux amd64 or arm64, install git, binutils, musl-tools, Rust/rustup and Python 3.11+:

```sh
rustup toolchain install stable --profile minimal
RUSTUP_TOOLCHAIN=stable ./build-static-rbw.sh
python3 scan-dependencies.py work/source/Cargo.lock dist
```

Use a fresh `WORK_DIR` for each build; `WORK_DIR`, `DIST_DIR`, `ARCH`, and `SOURCE_SHA` are optional overrides. Cross compilation is not configured: use a native machine/runner for each architecture. Build dependencies and OSV require network access. Build failures leave the last published release intact.
