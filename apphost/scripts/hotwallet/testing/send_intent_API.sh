#!/usr/bin/env bash
set -euo pipefail

BASE="http://localhost:8080/api/v1/request"

CONTAINER="hotwallet-btc-core"

# ----------------------------------------------------------------------------
# rpc_call <wallet> <method> [params...]
#   Params müssen bereits im passenden Format übergeben werden:
#   Strings direkt, JSON-Werte (Listen/Objekte/Zahlen/Bools) als JSON-String.
# ----------------------------------------------------------------------------
rpc_call() {
    local wallet="$1" method="$2"
    shift 2
    docker exec "$CONTAINER" bitcoin-cli -regtest \
        -datadir=/home/app/.bitcoin \
        -rpcwallet="$wallet" \
        "$method" "$@"
}

# ----------------------------------------------------------------------------
# TEST BIP21
# ----------------------------------------------------------------------------
test_bip21() {
    local wallet_name_target="$1"

    local new_address
    new_address="$(rpc_call "$wallet_name_target" getnewaddress "BIP21-Test" "bech32")"
    echo "Generierte Adresse für ${wallet_name_target}: ${new_address}"

    # Metadaten für den BIP-21
    local amount="0.012"
    local label message
    label="$(jq -rn --arg s "Luke Dashjr" '$s|@uri')"                 # URL-Encoding
    message="$(jq -rn --arg s "Donation to Luke & friends" '$s|@uri')"

    # dynamische BIP-21 URI
    local bip21_uri="bitcoin:${new_address}?amount=${amount}&label=${label}&message=${message}"

    local payload
    payload="$(jq -cn --arg uri "$bip21_uri" '{uri: $uri}')"

    echo -n "BIP21 Server Response: "
    curl -sS -X POST "${BASE}/bip21" \
        -H "Content-Type: application/json" \
        -d "$payload"
    echo
}

# ----------------------------------------------------------------------------
# TEST PSBT
# ----------------------------------------------------------------------------
test_psbt() {
    local wallet_name_target="$1" wallet_name_source="$2" lockTime="$3"

    local target_address
    target_address="$(rpc_call "$wallet_name_target" getnewaddress "BIP21-Empfang" "bech32")"
    echo " Zieladresse (${wallet_name_target}): ${target_address}"

    # outputs: [{ "<addr>": 0.012 }]
    local outputs
    outputs="$(jq -cn --arg a "$target_address" '[{($a): 0.012}]')"

    # Options-Objekt (fee_rate bewusst nicht gesetzt -> Core/OPA übernimmt Kontrolle)
    local options
    options='{
        "add_inputs": true,
        "conf_target": 6,
        "includeWatching": true,
        "replaceable": true,
        "estimate_mode": "conservative"
    }'

    # walletcreatefundedpsbt [] outputs locktime options bip32derivs
    local funded
    funded="$(rpc_call "$wallet_name_source" walletcreatefundedpsbt \
        '[]' "$outputs" "$lockTime" "$options" true)"

    local final_psbt_base64
    final_psbt_base64="$(printf '%s' "$funded" | jq -r '.psbt')"
    echo " PSBT via 'walletcreatefundedpsbt' generiert."

    local payload
    payload="$(jq -cn --arg p "$final_psbt_base64" '{psbt: $p}')"

    echo -n " Server Response für /psbt: "
    curl -sS -X POST "${BASE}/psbt" \
        -H "Content-Type: application/json" \
        -d "$payload"
    echo
}

# ----------------------------------------------------------------------------
# RUN
# ----------------------------------------------------------------------------
main() {
    test_bip21 "wallet2"
    test_psbt "wallet2" "keyA" 6
}

main "$@"
