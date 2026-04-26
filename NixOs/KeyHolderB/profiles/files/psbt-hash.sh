#!/usr/bin/env bash
set -euo pipefail

FILE="$1"
if [ -z "$FILE" ]; then
  echo "Usage: psbt-hash.sh <file.psbt>"
  exit 1
fi

sha256sum "$FILE"