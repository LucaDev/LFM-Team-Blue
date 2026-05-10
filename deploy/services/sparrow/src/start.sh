#!/bin/bash
# Start script for Sparrow Server with environment variables

# Set default values if not provided
BITCOIN_RPC_HOST=${BITCOIN_RPC_HOST:-bitcoind-regtest.btc-net.svc.cluster.local}
BITCOIN_RPC_PORT=${BITCOIN_RPC_PORT:-8332}
BITCOIN_RPC_USER=${BITCOIN_RPC_USER:-user}
BITCOIN_RPC_PASSWORD=${BITCOIN_RPC_PASSWORD:-pass}
SPARROW_SERVER_PORT=${SPARROW_SERVER_PORT:-8080}

# Create config directory if needed
mkdir -p /root/.sparrow

# Run Sparrow in server mode
java -jar sparrow.jar --server --rpcuser=$BITCOIN_RPC_USER --rpcpassword=$BITCOIN_RPC_PASSWORD --rpchost=$BITCOIN_RPC_HOST --rpcport=$BITCOIN_RPC_PORT --serverport=$SPARROW_SERVER_PORT