#!/usr/bin/python3
import os
import re
import subprocess
import sys
from typing import List


def _main(command: List[str]) -> None:
    srcroot = os.getenv("SRCROOT")
    if not srcroot:
        sys.exit("SRCROOT environment variable must be set")

    should_strip_color = os.getenv("COLOR_DIAGNOSTICS", default="YES") != "YES"

    strip_color = re.compile(r"\x1b\[[0-9;]{1,}[A-Za-z]")
    relative_diagnostic = re.compile(
        r"^[^/].+/.+:\d+(:\d+)?: (error|warning):"
    )
    # \g<0> is the entire regex match.
    diagnostic_prefix = rf"{srcroot}/\g<0>"

    process = subprocess.Popen(
        command, bufsize=1, stderr=subprocess.PIPE, universal_newlines=True
    )
    assert process.stderr

    while process.poll() is None:
        input_line = process.stderr.readline().rstrip()

        if should_strip_color:
            input_line = strip_color.sub("", input_line)

        if not input_line:
            continue

        output_line = relative_diagnostic.sub(diagnostic_prefix, input_line)
        print(output_line, flush=True)

    sys.exit(process.returncode)


if __name__ == "__main__":
    _main(sys.argv[1:])
