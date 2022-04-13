#!/bin/bash

set -euo pipefail

if [ "${ENABLE_PREVIEWS:-NO}" == "YES" ]; then
  exit
fi

readonly index_stores_file="$1"

# Exit early from builds that don't update any indexes.
if [[ ! -s "$index_stores_file" ]]; then
  exit
fi

# Input: /Users/dlee/Library/Developer/Xcode/DerivedData/Lyft-cfqcoxftkyacmpgkfdouziiylmtt/Build/Products
# Output: /Users/dlee/Library/Developer/Xcode/DerivedData/Lyft-cfqcoxftkyacmpgkfdouziiylmtt
derived_data_root=$(dirname "$(dirname "$BUILD_DIR")")
readonly xcode_index_root="$derived_data_root/Index/DataStore"

# Example: /private/var/tmp/_bazel_dlee/bab34722cdede8a481e31ae83e2bdfff/execroot/lyftios
readonly bazel_root="^/private/var/tmp/.+?/.+?/execroot/lyftios"

# Captures: 1) module name
readonly bazel_swiftmodules="^/__build_bazel_rules_swift/swiftmodules/(.+).swiftmodule"
readonly xcode_swiftmodules="$BUILT_PRODUCTS_DIR/\$1.swiftmodule/${ARCHS}.swiftmodule"

# Captures: 1) target name, 2) object name
# Note: The Bazel target name can contain a `.library` suffix, and the capture
# is written to avoid capturing it.
readonly bazel_objects="^bazel-out/.+?/bin/.*?(?:[^/]+)/([^/]+?)(?:[.]library)?_objs(?:/.*)*/(.+?)\.swift\.o$"
# Note: may want to use one of the env variables instead of assuming "-normal" in this path.
readonly xcode_objects="$CONFIGURATION_TEMP_DIR/\$1.build/Objects-normal/$ARCHS/\$2.o"

BAZEL_NO_TRACE=true ./bazelw run --config=lint --color=no -- "@index-import//:index-import" \
    -remap "$bazel_swiftmodules=$xcode_swiftmodules" \
    -remap "$bazel_objects=$xcode_objects" \
    -remap "$bazel_root=$SRCROOT" \
    -remap "^Modules/=$SRCROOT/Modules/" \
    -remap "/Applications/Xcode.*?[.]app/Contents/Developer=$DEVELOPER_DIR" \
    -incremental \
    @"$index_stores_file" \
    "$xcode_index_root"

# Record files are copied from bazel, which preserves r-xr-xr-x perms. Fix that.
chmod -R u+w "$xcode_index_root"
