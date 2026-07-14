#!/bin/sh
set -eu

SECTION="/root/ailab2-iac/section-05-backup-monitoring"
VALIDDIR="$SECTION/validation"
RUNTIME="/root/ailab-runtime/borg-host-to-104"
CURRENT="/var/lib/ailab-backup/staging/current"

mkdir -p "$VALIDDIR"

export BORG_RSH="ssh -i $RUNTIME/id_ed25519 -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$RUNTIME/known_hosts"
export BORG_PASSCOMMAND="/usr/bin/cat $RUNTIME/passphrase"
export BORG_REPO="ssh://borgrepo@10.40.40.104/srv/backup/repos/host"

check_tcp() {
  host="$1"
  port="$2"
  python3 - <<PY
import socket
host = "$host"
port = int("$port")
s = socket.socket()
s.settimeout(2.0)
try:
    s.connect((host, port))
except Exception:
    print("blocked")
else:
    print("open")
finally:
    s.close()
PY
}

pct exec 103 -- sh -lc '
python3 - <<'"'"'PY'"'"'
import socket
targets = [("10.30.30.1", 9100), ("10.30.30.1", 8006), ("10.30.30.1", 22), ("10.30.30.1", 111), ("10.30.30.1", 3128), ("10.10.10.10", 9100), ("10.40.40.104", 9100)]
for host, port in targets:
    s = socket.socket()
    s.settimeout(2.0)
    try:
        s.connect((host, port))
    except Exception:
        state = "blocked"
    else:
        state = "open"
    finally:
        s.close()
    print(f"{host}:{port}={state}")
PY' >"$VALIDDIR/103-zone-connectivity.txt"

pct exec 103 -- python3 - <<'PY' >"$VALIDDIR/103-prometheus-ready.txt"
import urllib.request
print(urllib.request.urlopen("http://10.30.30.103:9090/-/ready", timeout=5).read().decode())
PY
pct exec 103 -- python3 - <<'PY' >"$VALIDDIR/103-alertmanager-ready.txt"
import urllib.request
print(urllib.request.urlopen("http://10.30.30.103:9093/-/ready", timeout=5).read().decode())
PY
pct exec 103 -- python3 - <<'PY' >"$VALIDDIR/103-ntfy-root.html"
import urllib.request
print(urllib.request.urlopen("http://10.30.30.103:2586/", timeout=5).read().decode())
PY
pct exec 103 -- python3 - <<'PY' >"$VALIDDIR/103-blackbox-ntfy.txt"
import urllib.request
print(urllib.request.urlopen("http://10.30.30.103:9115/probe?module=http_2xx&target=http://10.30.30.103:2586/", timeout=5).read().decode())
PY
pct exec 103 -- python3 - <<'PY' >"$VALIDDIR/103-prometheus-targets.json"
import urllib.request
print(urllib.request.urlopen("http://10.30.30.103:9090/api/v1/targets", timeout=5).read().decode())
PY

check_tcp 10.40.40.104 22 >"$VALIDDIR/host-to-104-ssh.txt"
ssh -i "$RUNTIME/id_ed25519" -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$RUNTIME/known_hosts" borgrepo@10.40.40.104 true >"$VALIDDIR/104-borgrepo-shell-check.txt" 2>&1 || true
borg list >"$VALIDDIR/borg-list.txt"
LATEST="$(cat "$SECTION/validation/latest-borg-archive.txt")"
TMPDIR="$(mktemp -d /tmp/ailab-smoke-restore.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT
(cd "$TMPDIR" && borg extract "::${LATEST}" host/configs.tgz ct-101/EXCLUSIONS.txt ct-101/sanitized-configs.tgz)
find "$TMPDIR" -type f | sort >"$VALIDDIR/borg-smoke-restore-files.txt"
tar -tzf "$TMPDIR/host/configs.tgz" | sort | sed -n '1,200p' >"$VALIDDIR/borg-smoke-restore-host-configs.txt"
tar -tzf "$TMPDIR/ct-101/sanitized-configs.tgz" | sort | sed -n '1,200p' >"$VALIDDIR/borg-smoke-restore-101-configs.txt"
sha256sum "$TMPDIR/host/configs.tgz" "$TMPDIR/ct-101/sanitized-configs.tgz" "$TMPDIR/ct-101/EXCLUSIONS.txt" >"$VALIDDIR/borg-smoke-restore-sha256.txt"

pct config 103 >"$VALIDDIR/103-pct-config-final.txt"
pct config 104 >"$VALIDDIR/104-pct-config-final.txt"
pct status 101 >"$VALIDDIR/101-status-final.txt"
pct status 103 >"$VALIDDIR/103-status-final.txt"
pct status 104 >"$VALIDDIR/104-status-final.txt"

find "$CURRENT" -maxdepth 3 -type f | sort >"$VALIDDIR/current-staging-files.txt" 2>/dev/null || true
