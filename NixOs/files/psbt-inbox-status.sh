#!/usr/bin/env bash
set -euo pipefail

echo "=== Incoming PSBTs ==="
if [ -d "$HOME/psbt/in" ]; then
  ls -lh "$HOME/psbt/in" || echo "Inbox empty"
else
  echo "PSBT inbox missing!"
fi