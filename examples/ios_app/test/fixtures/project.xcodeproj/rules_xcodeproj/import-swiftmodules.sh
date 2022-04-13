#!/bin/bash

set -euo pipefail

# Sync the entire set of swiftmodule and swiftdoc files to the Xcode products
# directory. This ensures that integrated tools, like lldb and the indexing
# system, can find and consume the project's modules.

readonly collected_outputs_path="$1"

tr '\n' '\0' < "$collected_outputs_path/swiftmodules.txt" \
  | /usr/bin/xargs -0 -n 1 -P 8 ./tools/xcbazel/sync-swiftmodule.sh swiftmodule

tr '\n' '\0' < "$collected_outputs_path/swiftdocs.txt" \
  | /usr/bin/xargs -0 -n 1 -P 8 ./tools/xcbazel/sync-swiftmodule.sh swiftdoc
