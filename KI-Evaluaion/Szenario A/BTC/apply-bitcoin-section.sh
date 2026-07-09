#!/usr/bin/env bash
set -euo pipefail

SYNC_DIR=/root/homelab-config-sync
SECRETS_DIR=/root/homelab-secrets
STAGING_DIR=/root/homelab-staging
BTC_VERSION=31.0
BTC_ARCHIVE="bitcoin-${BTC_VERSION}-x86_64-linux-gnu.tar.gz"
BTC_BASE_URL="https://bitcoincore.org/bin/bitcoin-core-${BTC_VERSION}"

required_files=(
  "$SYNC_DIR/bitcoin.conf"
  "$SYNC_DIR/tor-bitcoin.conf"
  "$SYNC_DIR/bitcoind.service"
  "$SYNC_DIR/homelab-btc-firewall.sh"
  "$SYNC_DIR/homelab-btc-firewall.service"
  "$SYNC_DIR/bitcoin-node-metrics.sh"
  "$SYNC_DIR/bitcoin-node-metrics.service"
  "$SYNC_DIR/bitcoin-node-metrics.timer"
  "$SYNC_DIR/prometheus.yml"
  "$SYNC_DIR/homelab.rules.yml"
)

for file in "${required_files[@]}"; do
  [[ -f "$file" ]] || {
    echo "Missing required sync file: $file" >&2
    exit 1
  }
done

current_size="$(pct config 204 | awk -F'size=' '/^rootfs:/ {print $2}' | tr -d '\r\n')"
if [[ "$current_size" =~ ^([0-9]+)G$ ]]; then
  current_size_gb="${BASH_REMATCH[1]}"
else
  echo "Unable to parse current rootfs size for CT 204: $current_size" >&2
  exit 1
fi

if pct status 204 | grep -q 'running'; then
  pct shutdown 204 --timeout 60 || pct stop 204
fi

pct set 204 -cores 2 -memory 2048
if (( current_size_gb < 32 )); then
  pct resize 204 rootfs "+$((32 - current_size_gb))G"
fi

pct start 204

pct exec 204 -- bash -lc '
set -euo pipefail
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl jq tor iptables
install -d -m 0755 /etc/tor/torrc.d
if ! grep -qxF "%include /etc/tor/torrc.d/*.conf" /etc/tor/torrc; then
  printf "\n%%include /etc/tor/torrc.d/*.conf\n" >> /etc/tor/torrc
fi
'

pct exec 204 -- bash -lc "
set -euo pipefail
version='$BTC_VERSION'
archive='$BTC_ARCHIVE'
base_url='$BTC_BASE_URL'
tmp_dir=\$(mktemp -d)
trap 'rm -rf \"\$tmp_dir\"' EXIT

if ! id bitcoin >/dev/null 2>&1; then
  useradd --system --home /var/lib/bitcoind --shell /usr/sbin/nologin bitcoin
fi
usermod -aG debian-tor bitcoin

install -d -m 0750 -o bitcoin -g bitcoin /var/lib/bitcoind
install -d -m 0750 -o root -g bitcoin /etc/bitcoin
install -d -m 0755 /var/lib/prometheus/node-exporter-textfile

cd \"\$tmp_dir\"
curl -fsSLO \"\$base_url/\$archive\"
curl -fsSLO \"\$base_url/SHA256SUMS\"
grep \" \$archive\$\" SHA256SUMS | sha256sum -c -

tar -xzf \"\$archive\"
install -d /opt/bitcoin-core
rm -rf \"/opt/bitcoin-core/\${version}.new\"
mv \"bitcoin-\$version\" \"/opt/bitcoin-core/\${version}.new\"
systemctl stop bitcoind 2>/dev/null || true
rm -rf \"/opt/bitcoin-core/\$version\"
mv \"/opt/bitcoin-core/\${version}.new\" \"/opt/bitcoin-core/\$version\"
ln -sfn \"/opt/bitcoin-core/\$version\" /opt/bitcoin-core/current
"

install -d \
  "$STAGING_DIR/btc-node" \
  "$STAGING_DIR/ops/config/prometheus/alerts"

install -m 0644 "$SYNC_DIR/bitcoin.conf" "$STAGING_DIR/btc-node/bitcoin.conf"
install -m 0644 "$SYNC_DIR/tor-bitcoin.conf" "$STAGING_DIR/btc-node/tor-bitcoin.conf"
install -m 0644 "$SYNC_DIR/bitcoind.service" "$STAGING_DIR/btc-node/bitcoind.service"
install -m 0644 "$SYNC_DIR/prometheus.yml" "$STAGING_DIR/ops/config/prometheus/prometheus.yml"
install -m 0644 "$SYNC_DIR/homelab.rules.yml" "$STAGING_DIR/ops/config/prometheus/alerts/homelab.rules.yml"

pct push 204 "$SYNC_DIR/bitcoin.conf" /etc/bitcoin/bitcoin.conf
pct push 204 "$SYNC_DIR/tor-bitcoin.conf" /etc/tor/torrc.d/bitcoin.conf
pct push 204 "$SYNC_DIR/bitcoind.service" /etc/systemd/system/bitcoind.service
pct push 204 "$SYNC_DIR/homelab-btc-firewall.sh" /usr/local/sbin/homelab-btc-firewall.sh
pct push 204 "$SYNC_DIR/homelab-btc-firewall.service" /etc/systemd/system/homelab-btc-firewall.service
pct push 204 "$SYNC_DIR/bitcoin-node-metrics.sh" /usr/local/sbin/bitcoin-node-metrics.sh
pct push 204 "$SYNC_DIR/bitcoin-node-metrics.service" /etc/systemd/system/bitcoin-node-metrics.service
pct push 204 "$SYNC_DIR/bitcoin-node-metrics.timer" /etc/systemd/system/bitcoin-node-metrics.timer

pct exec 204 -- bash -lc '
set -euo pipefail
chown root:bitcoin /etc/bitcoin/bitcoin.conf
chmod 0640 /etc/bitcoin/bitcoin.conf
chmod 0644 /etc/tor/torrc.d/bitcoin.conf
chmod 0644 /etc/systemd/system/bitcoind.service /etc/systemd/system/homelab-btc-firewall.service /etc/systemd/system/bitcoin-node-metrics.service /etc/systemd/system/bitcoin-node-metrics.timer
chmod 700 /usr/local/sbin/homelab-btc-firewall.sh /usr/local/sbin/bitcoin-node-metrics.sh
touch /etc/default/prometheus-node-exporter
if grep -q "^ARGS=" /etc/default/prometheus-node-exporter; then
  current_args="$(sed -n '\''s/^ARGS="\([^"]*\)".*/\1/p'\'' /etc/default/prometheus-node-exporter | head -n1)"
  if [[ "$current_args" != *"--collector.textfile.directory=/var/lib/prometheus/node-exporter-textfile"* ]]; then
    if [[ -n "$current_args" ]]; then
      new_args="$current_args --collector.textfile.directory=/var/lib/prometheus/node-exporter-textfile"
    else
      new_args="--collector.textfile.directory=/var/lib/prometheus/node-exporter-textfile"
    fi
    sed -i "s|^ARGS=.*|ARGS=\"$new_args\"|" /etc/default/prometheus-node-exporter
  fi
else
  printf '\''ARGS="--collector.textfile.directory=/var/lib/prometheus/node-exporter-textfile"\n'\'' >> /etc/default/prometheus-node-exporter
fi
systemctl daemon-reload
systemctl restart tor
systemctl restart prometheus-node-exporter
systemctl enable --now homelab-btc-firewall.service
systemctl enable --now bitcoind
systemctl enable --now bitcoin-node-metrics.timer
/usr/local/sbin/bitcoin-node-metrics.sh
'

pct push 203 "$SYNC_DIR/prometheus.yml" /opt/homelab/ops/config/prometheus/prometheus.yml
pct push 203 "$SYNC_DIR/homelab.rules.yml" /opt/homelab/ops/config/prometheus/alerts/homelab.rules.yml
pct exec 203 -- bash -lc '
set -euo pipefail
cd /opt/homelab/ops
docker compose restart prometheus
'

pct exec 204 -- bash -lc '
set -euo pipefail
for _ in $(seq 1 60); do
  if /opt/bitcoin-core/current/bin/bitcoin-cli -conf=/etc/bitcoin/bitcoin.conf -datadir=/var/lib/bitcoind getblockchaininfo >/tmp/blockchaininfo.json 2>/dev/null; then
    exit 0
  fi
  sleep 5
done
systemctl status bitcoind --no-pager -l || true
exit 1
'

onion_address=""
for _ in $(seq 1 24); do
  onion_address="$(pct exec 204 -- bash -lc '/opt/bitcoin-core/current/bin/bitcoin-cli -conf=/etc/bitcoin/bitcoin.conf -datadir=/var/lib/bitcoind getnetworkinfo 2>/dev/null | jq -r '\''[.localaddresses[]? | select((.network // "") == "onion" or ((.address // "") | endswith(".onion"))) | .address] | first // empty'\''' | tr -d '\r\n')"
  if [[ -n "$onion_address" ]]; then
    break
  fi
  sleep 5
done

if [[ -n "$onion_address" ]]; then
  cat >"$SECRETS_DIR/bitcoin-node.txt" <<EOF
Bitcoin node onion (P2P only, not a browser URL)
- ${onion_address}:8333
EOF
  chmod 600 "$SECRETS_DIR/bitcoin-node.txt"

  sed -i '/^Bitcoin Node P2P Onion$/,/^$/d' "$SECRETS_DIR/service-credentials.txt" 2>/dev/null || true
  cat >>"$SECRETS_DIR/service-credentials.txt" <<EOF

Bitcoin Node P2P Onion
- ${onion_address}:8333
EOF
  chmod 600 "$SECRETS_DIR/service-credentials.txt"
fi
