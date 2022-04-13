#!/bin/bash

set -euo pipefail

_cp() {
    # Prefer clonefile, but fallback to regular copies.
    cp -c "$@" 2> /dev/null || cp "$@"
}

# We can be passed `swiftmodule` or `swiftdoc`
readonly extension=$1
readonly file=$2
readonly swiftmodule="${2%.$extension}.swiftmodule"

# Construct the path to the Xcode swiftmodule bundle
module_name="$(basename "$swiftmodule")"
readonly bundle_dir="$BUILT_PRODUCTS_DIR/$module_name"
if [[ ! -d "$bundle_dir" ]]; then
  mkdir -p "$bundle_dir"
fi

dirs=("$bundle_dir")

# We don't index when building SwiftUI Previews
if [[ "${ENABLE_PREVIEWS:-NO}" != "YES" ]]; then
  # Indexing requires swiftmodules in a different Index-rooted build directory
  readonly index_bundle_dir="${bundle_dir/\/Build\/Products\///Index/Build/Products/}"
  if [[ ! -d "$index_bundle_dir" ]]; then
    mkdir -p "$index_bundle_dir"
  fi

  dirs+=("$index_bundle_dir")
fi

readonly arch_files=(
  "$ARCHS.$extension"
  "$ARCHS-apple-ios${LLVM_TARGET_TRIPLE_SUFFIX:-}.$extension"
)

# Copy bazel-out/*/bin/Modules/Foo/Foo.swift{module,doc} to
# DerivedData $BUILT_PRODUCTS_DIR/Foo.swiftmodule/x86_64.swift{module,doc}
for dir in "${dirs[@]}"; do
  for arch_file in "${arch_files[@]}"; do
    rm -f "$dir/$arch_file"
    _cp "$file" "$dir/$arch_file"
  done

  # Bazel produces files without write perm, but this messes with Xcode.
  chmod -R +w "$dir"
done
