#!/usr/bin/env bash
set -euo pipefail

echo "=== Signed PSBTs ==="
ls -lh "$HOME/psbt/out" || echo "No signed PSBTs yet"