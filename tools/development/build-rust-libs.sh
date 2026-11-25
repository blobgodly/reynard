#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

RUST_WORKSPACE="$REPO_ROOT/rust-libs"
FFI_DIR="$RUST_WORKSPACE/reynard-ffi"
OUTPUT_DIR="$REPO_ROOT/browser/Reynard/RustLibs"
OUTPUT_LIB="$OUTPUT_DIR/libreynard_ffi.a"
OUTPUT_HEADER="$OUTPUT_DIR/reynard_ffi.h"

TARGET_DIR="$RUST_WORKSPACE/target"
DEPLOYMENT_TARGET="13.0"
RUST_TARGET="aarch64-apple-ios"
DEPLOYMENT_FLAG="-miphoneos-version-min=${DEPLOYMENT_TARGET}"

echo "==> Checking rustup target for $RUST_TARGET..."
if ! rustup target list | grep -q "^$RUST_TARGET (installed)"; then
    rustup target add "$RUST_TARGET"
fi

export IPHONEOS_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"
if [ -n "${RUSTFLAGS:-}" ]; then
    export RUSTFLAGS="${RUSTFLAGS} -C link-arg=${DEPLOYMENT_FLAG}"
else
    export RUSTFLAGS="-C link-arg=${DEPLOYMENT_FLAG}"
fi
export TARGET_DIR
export CARGO_TARGET_DIR="$TARGET_DIR"

echo "==> Building reynard-ffi for $RUST_TARGET (Release)..."
mkdir -p "$OUTPUT_DIR"
cd "$RUST_WORKSPACE"
cargo build --release --package reynard-ffi --target "$RUST_TARGET"

echo "==> Copying static library to $OUTPUT_LIB..."
cp "$TARGET_DIR/$RUST_TARGET/release/libreynard_ffi.a" "$OUTPUT_LIB"

echo "==> Copying C header to $OUTPUT_HEADER..."
cp "$FFI_DIR/include/reynard_ffi.h" "$OUTPUT_HEADER"

echo "==> Build completed successfully!"
