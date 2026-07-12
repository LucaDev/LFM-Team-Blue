#!/bin/bash
set -e

RPC="docker exec hotwallet-btc-core bitcoin-cli -regtest -datadir=/home/app/.bitcoin"

ADDR1=$($RPC -rpcwallet=keyA getnewaddress)
ADDR2=$($RPC -rpcwallet=cold-multi getnewaddress)

$RPC -rpcwallet=wallet1 sendtoaddress "$ADDR1" 5
$RPC -rpcwallet=wallet1 sendtoaddress "$ADDR2" 25

$RPC -rpcwallet=wallet1 sendtoaddress "$ADDR1" 1
$RPC -rpcwallet=wallet1 sendtoaddress "$ADDR2" 1

ADDR3=$($RPC -rpcwallet=wallet1 getnewaddress)

$RPC generatetoaddress 1 "$ADDR3"