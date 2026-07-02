from prometheus_client import Counter, Gauge

# Ingress (HTTP-Schnittstellen)
INTENTS_TOTAL        = Counter("btc_intents_total", "Externe Zahlungsanfragen", ["rail"])          # bip21|psbt|manual
# Bau (vom tx-builder via NATS gemeldet)
PSBT_BUILT_TOTAL     = Counter("btc_psbt_built_total", "PSBTs gebaut", ["result"])                 # ok|failed
# Autorisierung
OPA_DECISIONS_TOTAL  = Counter("btc_opa_decisions_total", "OPA hot-tx Entscheidungen", ["result"]) # allow|deny
VELOCITY_BLOCK_TOTAL = Counter("btc_velocity_block_total", "Durch Daily-Limit abgelehnt")
WHITELIST_BLOCK_TOTAL= Counter("btc_whitelist_block_total", "Durch Whitelist abgelehnt")
# Balance-/Refill-Logik
REFILL_TOTAL         = Counter("btc_refill_decisions_total", "OPA-Balance-Aktion", ["action"])     # hold|hot_to_cold|cold_to_hot
# Signieren / Broadcast
PSBT_SIGNED_TOTAL    = Counter("btc_psbt_signed_total", "Signierergebnis", ["result"])             # ok|failed
BROADCAST_TOTAL      = Counter("btc_broadcast_total", "Broadcast-Ergebnis", ["flow", "result"])    # hot|cold  x  ok|finalize_failed|broadcast_failed
# Zustände
HOT_BALANCE_BTC      = Gauge("btc_hot_balance_btc", "Hot-Wallet-Saldo (BTC)")
WAITING_HUMAN        = Gauge("btc_waiting_human_psbts", "Wartende Cold-Refill-PSBTs")