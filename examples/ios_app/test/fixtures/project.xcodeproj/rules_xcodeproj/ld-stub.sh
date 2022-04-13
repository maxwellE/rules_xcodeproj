#!/bin/bash

set -euo pipefail

for arg in "$@"; do
  if [[ $arg == *_dependency_info.dat ]]; then
    ld_version=$(ld -v 2>&1 | grep ^@)
    printf "\0%s\0" "$ld_version" > "$arg"
  fi
done
