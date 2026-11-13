#!/usr/bin/env bash
set -euo pipefail

# The workflow resolves enhanced once; both architectures build the same commit.
SOURCE_REPO=https://github.com/rylos/rbw.git
SOURCE_BRANCH=enhanced
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
WORK_DIR=${WORK_DIR:-"$PWD/work"}
DIST_DIR=${DIST_DIR:-"$PWD/dist"}
case "${ARCH:-$(uname -m)}" in
    amd64|x86_64) arch=amd64; target=x86_64-unknown-linux-musl ;;
    arm64|aarch64) arch=arm64; target=aarch64-unknown-linux-musl ;;
    *) echo 'Supported architectures: amd64, arm64' >&2; exit 1 ;;
esac
mkdir -p "$WORK_DIR" "$DIST_DIR"
DIST_DIR=$(realpath "$DIST_DIR")
source_dir="$WORK_DIR/source"
if [[ -e "$source_dir" ]]; then
    echo "Use a fresh WORK_DIR (already exists: $source_dir)" >&2
    exit 1
fi
source_sha=${SOURCE_SHA:-$(git ls-remote "$SOURCE_REPO" "refs/heads/$SOURCE_BRANCH" | cut -f1)}
[[ "$source_sha" =~ ^[0-9a-f]{40}$ ]] || { echo 'Invalid source SHA' >&2; exit 1; }
git init -q "$source_dir"
git -C "$source_dir" remote add origin "$SOURCE_REPO"
git -C "$source_dir" fetch --depth=1 origin "$source_sha"
git -C "$source_dir" checkout --detach FETCH_HEAD
[[ $(git -C "$source_dir" rev-parse HEAD) == "$source_sha" ]]
cd "$source_dir"
for patch in "$SCRIPT_DIR"/patches/*.patch; do
    git apply --check "$patch"
    git apply "$patch"
done
rustup target add "$target"
export CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER=musl-gcc
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER=musl-gcc
export CC=musl-gcc
cargo test --locked --target "$target" --all-targets
cargo build --locked --release --target "$target" --bins
package="$DIST_DIR/package-$arch"
mkdir -p "$package"
for binary in rbw rbw-agent; do
    binary_path="target/$target/release/$binary"
    if readelf -l "$binary_path" | grep -q INTERP; then
        echo "$binary has a dynamic interpreter" >&2; exit 1
    fi
    if readelf -d "$binary_path" | grep -q NEEDED; then
        echo "$binary has shared-library dependencies" >&2; exit 1
    fi
    install -m755 "$binary_path" "$package/$binary"
done
"target/$target/release/rbw" --version
install -m644 LICENSE Cargo.lock "$package/"
mkdir -p "$package/patches"
cp "$SCRIPT_DIR"/patches/*.patch "$package/patches/"
{
    printf 'repository=%s\nbranch=%s\ncommit=%s\ntarget=%s\n' "$SOURCE_REPO" "$SOURCE_BRANCH" "$source_sha" "$target"
    rustc --version
    cargo --version
    printf 'cargo_lock_sha256='
    sha256sum Cargo.lock | cut -d' ' -f1
    printf 'patch_sha256 (see bundled patches/):\n'
    (cd "$SCRIPT_DIR" && sha256sum patches/*.patch)
    printf 'builder_commit=%s\n' "${BUILDER_SHA:-unknown}"
} > "$package/BUILD-INFO.txt"
tar -C "$package" -czf "$DIST_DIR/rbw-enhanced-linux-$arch.tar.gz" rbw rbw-agent LICENSE Cargo.lock BUILD-INFO.txt patches
cp "$package/BUILD-INFO.txt" "$DIST_DIR/BUILD-INFO-$arch.txt"
