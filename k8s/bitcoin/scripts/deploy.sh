#!/bin/bash
set -e

echo "Deploying Bitcoin stack..."

kubectl apply -f namespace.yaml
kubectl apply -f configmap-bitcoin.yaml
kubectl apply -f service-bitcoin.yaml
kubectl apply -f statefulset-bitcoin.yaml

echo "Waiting for Bitcoin nodes to be ready..."
kubectl wait --for=condition=ready pod -l app=bitcoind -n bitcoin --timeout=180s

echo "Running init job (mining)..."
kubectl apply -f job-init-mining.yaml

echo "Done."