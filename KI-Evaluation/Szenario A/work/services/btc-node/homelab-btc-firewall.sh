#!/usr/bin/env bash
set -euo pipefail

CHAIN=HOMELAB-BTC-ACCESS
RULE=(-p tcp -m multiport --dports 8332,8333,9100 -j "$CHAIN")

iptables -N "$CHAIN" 2>/dev/null || true
iptables -F "$CHAIN"

if ! iptables -C INPUT "${RULE[@]}" 2>/dev/null; then
  iptables -I INPUT 1 "${RULE[@]}"
fi

iptables -A "$CHAIN" -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
iptables -A "$CHAIN" -i lo -j RETURN
iptables -A "$CHAIN" -p tcp --dport 9100 -s 10.10.20.20/32 -j RETURN
iptables -A "$CHAIN" -j DROP
