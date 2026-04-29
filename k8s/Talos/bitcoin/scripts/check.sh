#!/bin/bash

echo "Pods:"
kubectl get pods -n bitcoin

echo ""
echo "Blockchain info:"
kubectl exec -it bitcoind-0 -n bitcoin -- \
bitcoin-cli -regtest getblockchaininfo