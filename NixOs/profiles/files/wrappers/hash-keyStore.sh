#!/usr/bin/env bash
set -euo pipefail

# 1) Echten Pfad dieses Wrappers ermitteln (Symlink wird aufgelöst)
SELF="$(readlink -f "$0")"
WRAPPER_DIR="$(dirname "$SELF")"

# 2) Zielscript relativ zum echten Wrapper-Verzeichnis bestimmen
TARGET="$WRAPPER_DIR/../auth/hash-keyStore.sh"

# 3) Optional: Existenz prüfen (hilft beim Debuggen)
if [[ ! -x "$TARGET" ]]; then
  # Falls nicht executable: Hinweis + trotzdem versuchen (oder exit 1)
  echo "ERROR: Zielscript nicht ausführbar oder nicht gefunden: $TARGET" >&2
  echo "Tipp: chmod +x \"$TARGET\"" >&2
  exit 1
fi

# 4) Root-Abfrage + Terminal offen halten + Ausgabe sichtbar
exec pkexec env DISPLAY="${DISPLAY:-}" XAUTHORITY="${XAUTHORITY:-}" \
  xfce4-terminal --hold --command \
  "bash -lc '\"$TARGET\"; echo; read -n1 -rsp \"Taste zum Schließen…\"'"