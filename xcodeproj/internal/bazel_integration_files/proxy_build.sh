#!/bin/bash

set -euo pipefail

"$BAZEL_INTEGRATION_DIR/generate_bazel_dependencies.sh"

"$BAZEL_INTEGRATION_DIR/copy_outputs.sh" \
    "_BazelForcedCompile_.swift" \
    "$BAZEL_INTEGRATION_DIR/app.exclude.rsynclist"
