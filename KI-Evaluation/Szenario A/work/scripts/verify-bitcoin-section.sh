#!/usr/bin/env bash
set -euo pipefail

echo "BTC_NODE_CONFIG"
pct config 204
echo

echo "BTC_NODE_SERVICES"
pct exec 204 -- sh -lc 'systemctl is-active tor bitcoind prometheus-node-exporter homelab-btc-firewall.service bitcoin-node-metrics.timer'
echo

echo "BTC_NODE_BINDINGS"
pct exec 204 -- sh -lc 'ss -ltn | grep -E ":(8332|8333|9050|9051|9100) " || true'
echo

echo "BTC_NODE_BLOCKCHAININFO"
pct exec 204 -- sh -lc '/opt/bitcoin-core/current/bin/bitcoin-cli -conf=/etc/bitcoin/bitcoin.conf -datadir=/var/lib/bitcoind getblockchaininfo | jq "{chain, blocks, headers, initialblockdownload, verificationprogress, pruned, size_on_disk}"'
echo

echo "BTC_NODE_NETWORKINFO"
pct exec 204 -- sh -lc '/opt/bitcoin-core/current/bin/bitcoin-cli -conf=/etc/bitcoin/bitcoin.conf -datadir=/var/lib/bitcoind getnetworkinfo | jq "{connections, subversion, localaddresses}"'
echo

echo "BTC_NODE_METRICS"
pct exec 204 -- sh -lc 'curl -s http://127.0.0.1:9100/metrics | grep homelab_bitcoin | head -n 40'
echo

echo "BTC_NODE_FIREWALL"
pct exec 204 -- sh -lc 'iptables -S HOMELAB-BTC-ACCESS'
echo

echo "PROMETHEUS_BTC_QUERIES"
pct exec 203 -- sh -lc 'curl -sG --data-urlencode '\''query=homelab_bitcoin_rpc_up{instance="10.10.10.30:9100"}'\'' http://127.0.0.1:9090/api/v1/query | jq -c .'
pct exec 203 -- sh -lc 'curl -sG --data-urlencode '\''query=up{job="node-exporters",instance="10.10.10.30:9100"}'\'' http://127.0.0.1:9090/api/v1/query | jq -c .'
