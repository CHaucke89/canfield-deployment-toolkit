#!/usr/bin/env bash
# Rebuilds the PNGs from a screenshots run's log (no artifact download needed).
# Usage: fetch-screenshots.sh <run-id> [out-dir]
set -euo pipefail
run=$1; out=${2:-screenshots}
mkdir -p "$out"
gh run view "$run" --log | python3 -c '
import sys, re, base64, os
out = sys.argv[1]; name = None; buf = []
for line in sys.stdin:
    text = re.sub(r"^.*?\d{4}-\d\d-\d\dT[\d:.]+Z ", "", line.rstrip("\n"))
    m = re.match(r"PNG-(BEGIN|END) (\S+)$", text)
    if m and m.group(1) == "BEGIN": name, buf = m.group(2), []
    elif m and name:
        open(os.path.join(out, name), "wb").write(base64.b64decode("".join(buf)))
        print(os.path.join(out, name)); name = None
    elif name: buf.append(text.strip())
' "$out"
