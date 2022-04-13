#!/usr/bin/python3

import os
import shutil
import sys
from typing import List

def _main() -> None:
    _touch_deps_files(sys.argv)
    _stub_dia(sys.argv)


def _touch_deps_files(args: List[str]) -> None:
    "Touch the Xcode-required .d files"
    flag = args.index("-MF")
    d_file = args[flag + 1]
    _touch(d_file)


def _stub_dia(args: List[str]) -> None:
    "Stub out the dia file"
    flag = args.index("--serialize-diagnostics")
    dia_file = args[flag + 1]
    print(__file__)
    print(os.path.realpath(__file__))
    stub_file = os.path.join(os.path.dirname(__file__), 'stub.dia')
    shutil.copyfile(stub_file, dia_file)


def _touch(path: str) -> None:
    # Don't open with "w" mode, that truncates the file if it exists.
    open(path, "a")


if __name__ == "__main__":
    _main()
