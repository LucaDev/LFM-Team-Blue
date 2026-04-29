#!/bin/bash
set -e

echo "Waiting for nodes..."
kubectl wait --for=condition=ready pod -l app=bitcoind -n bitcoin --timeout=180s

echo "Connecting nodes..."

kubectl exec -it bitcoind-0 -n bitcoin -- \
bitcoin-cli -regtest addnode "bitcoind-1.bitcoind:18444" onetry

kubectl exec -it bitcoind-0 -n bitcoin -- \
bitcoin-cli -regtest addnode "bitcoind-2.bitcoind:18444" onetry

echo "Nodes connected."