#!/usr/bin/python3
import json
import os
import re
import shutil
import subprocess
import sys
from typing import List

def _main() -> None:
    if sys.argv[1:] == ["-v"]:
        os.system("swiftc -v")
        return

    _touch_deps_files(sys.argv)
    _touch_swiftmodule_artifacts(sys.argv)


def _delete_framework_swiftmodules(args: List[str]) -> None:
    include_index = next(i for i, arg in enumerate(sys.argv) if arg == "-I")
    product_dir = sys.argv[include_index + 1]
    match = re.match(r".*\/Previews\/(.*?)\/Products\/[^\/]*$", product_dir)
    if not match:
        print(
            "Failed to parse name from products directory in arguments",
            file=sys.stderr,
        )
        exit(1)
    product_name = match.group(1)
    modules_dir = f"{product_dir}/{product_name}.framework/Modules"
    if os.path.exists(modules_dir):
        shutil.rmtree(modules_dir, ignore_errors=True)


def _touch_deps_files(args: List[str]) -> None:
    "Touch the Xcode-required .d files"
    flag = args.index("-output-file-map")
    output_file_map_path = args[flag + 1]

    with open(output_file_map_path) as f:
        output_file_map = json.load(f)

    d_files = [
        entry["dependencies"]
        for entry in output_file_map.values()
        if "dependencies" in entry
    ]

    for d_file in d_files:
        _touch(d_file)


def _touch_swiftmodule_artifacts(args: List[str]) -> None:
    "Touch the Xcode-required .swift{module,doc,sourceinfo} files"
    flag = args.index("-emit-module-path")
    swiftmodule_path = args[flag + 1]
    swiftdoc_path = _replace_ext(swiftmodule_path, "swiftdoc")
    swiftsourceinfo_path = _replace_ext(swiftmodule_path, "swiftsourceinfo")

    _touch(swiftmodule_path)
    _touch(swiftdoc_path)
    _touch(swiftsourceinfo_path)


def _touch(path: str) -> None:
    # Don't open with "w" mode, that truncates the file if it exists.
    open(path, "a")


def _replace_ext(path: str, extension: str) -> str:
    name, _ = os.path.splitext(path)
    return ".".join((name, extension))


if __name__ == "__main__":
    _main()
