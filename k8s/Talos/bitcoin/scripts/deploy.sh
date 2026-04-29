kubectl apply -f namespace.yaml
kubectl apply -f secret-rpc.yaml
kubectl apply -f configmap-bitcoin.yaml
kubectl apply -f service-bitcoin.yaml
kubectl apply -f statefulset-bitcoin.yaml

kubectl wait --for=condition=ready pod -l app=bitcoind -n bitcoin --timeout=180s

kubectl apply -f job-init-mining.yaml