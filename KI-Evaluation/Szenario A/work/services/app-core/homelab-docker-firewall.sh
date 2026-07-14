#!/usr/bin/env bash
set -euo pipefail

CHAIN=HOMELAB-DOCKER-ACCESS

iptables -N "$CHAIN" 2>/dev/null || true
iptables -F "$CHAIN"
iptables -C DOCKER-USER -j "$CHAIN" 2>/dev/null || iptables -I DOCKER-USER 1 -j "$CHAIN"

iptables -A "$CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
iptables -A "$CHAIN" -i lo -j RETURN
iptables -A "$CHAIN" -i docker+ -j RETURN
iptables -A "$CHAIN" -i br+ -j RETURN
iptables -A "$CHAIN" -s 10.10.10.2 -j RETURN
iptables -A "$CHAIN" -s 10.10.20.20 -j RETURN
iptables -A "$CHAIN" -j DROP
