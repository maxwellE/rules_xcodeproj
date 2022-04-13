#!/bin/bash

set -euo pipefail

# `customLLDBInitFile` has the side effect of not loading the user's lldbinit.
# If present, explicitly load it.
if [[ -f "$HOME/.lldbinit" ]]; then
  echo "command source ~/.lldbinit"
fi

# Change the pwd to support relative paths in binaries.
echo "platform settings -w \"$SRCROOT\""
echo

# Enable Lyft internal lldb commands.
echo "command script import \"$SRCROOT/tools/xcbazel/lyft_lldb.py\""
echo

# Explicitly specify the current Xcode's SDK path.
echo "settings set target.sdk-path \"$SDKROOT\""
echo

# Enable lldb type logging for debugging issues
echo "log enable lldb types -f \"$SRCROOT\"/tmp/logs/xcbazel/lldb-types.log"
echo

# Include Lyft's prebuilt frameworks in lldb's search path.
echo "settings set target.swift-framework-search-paths $FRAMEWORK_SEARCH_PATHS"
echo

# Make breakpoints work with Bazel builds.
#
# rules_swift passes `-debug-prefix-map "$PWD=."` to Swift compiles, which is
# only half the job. The other half is to remap `.` to the project root.
#
# For example, for a breakpoint in:
#     ./Modules/Foo/Sources/FooView.swift
# lldb needs to remap this to:
#     /Users/devname/Projects/Lyft-iOS/Modules/Foo/Sources/FooView.swift
echo "settings set target.source-map ./external/ \"$1\""
echo "settings append target.source-map ./ \"$SRCROOT\""
