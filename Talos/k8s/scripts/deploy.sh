#!/usr/bin/env bash
set -euo pipefail

kubectl apply -f deploy/k8s/base/namespace.yaml

kubectl apply -f deploy/k8s/base/nats.yaml
kubectl apply -f deploy/k8s/base/opa.yaml

# config/secrets live in base OR deploy/k8s/config depending on your choice
if [[ -f deploy/k8s/base/configmap.yaml ]]; then
  kubectl apply -f deploy/k8s/base/configmap.yaml
fi
if [[ -f deploy/k8s/base/secrets-template.yaml ]]; then
  echo "[!] NOTE: secrets-template.yaml is a template. Apply your real secret instead."
fi

kubectl apply -f deploy/k8s/bitcoin-net/bitcoind-regtest.yaml
kubectl apply -f deploy/k8s/bitcoin-net/miner.yaml

kubectl apply -f deploy/k8s/base/middleware.yaml
kubectl apply -f deploy/k8s/base/tx-builder.yaml
kubectl apply -f deploy/k8s/base/policy-signer.yaml

kubectl apply -f deploy/k8s/base/networkpolicies.yaml

echo "[*] Deployed."