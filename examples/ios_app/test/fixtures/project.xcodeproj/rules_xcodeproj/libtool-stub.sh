#!/bin/bash

set -euo pipefail

for arg in "$@"; do
  if [[ $arg == *_dependency_info.dat ]]; then
    libtool_version=$(libtool -V | cut -d " " -f4)
    printf "\0%s\0" "$libtool_version" > "$arg"
  fi
done
