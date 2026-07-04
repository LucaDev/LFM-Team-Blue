#!/usr/bin/env bash
set -euo pipefail

# Rotiert alle Hot-seitigen Geheimnisse (.env + rpcauth.conf) und zieht die
# Änderungen live nach (DB-Passwörter via ALTER, Neustart der betroffenen
# Container).

#HMAC out of scope, da von signer kontrolliert. Rotation nur über den USB-Weg (wgHMAC_export/import.sh).
#
# Verwendung:
#   sudo bash scripts/ops/setup/rotate_secrets.sh            # alles + Neustart
#   sudo NO_RESTART=1 bash scripts/ops/setup/rotate_secrets.sh   # nur .env/DB, kein Neustart

PROJECT_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"
RPCAUTH_FILE="${PROJECT_ROOT}/services/btc-core/src/rpcauth.conf"
COMPOSE="${PROJECT_ROOT}/docker-compose.yaml"

die(){ echo "ERROR: $*" >&2; exit 1; }
info(){ echo "[*] $*"; }

[[ -f "$ENV_FILE" ]] || die ".env fehlt – zuerst gen_secrets.sh ausführen"

# aktuelle Werte laden (Rollennamen, Compose-Interpolation)
set -a; source "$ENV_FILE"; set +a

# Backups (Zeitstempel), damit ein Rollback möglich bleibt
TS="$(date +%Y%m%d-%H%M%S)"
cp -a "$ENV_FILE" "${ENV_FILE}.bak.${TS}"
[[ -f "$RPCAUTH_FILE" ]] && cp -a "$RPCAUTH_FILE" "${RPCAUTH_FILE}.bak.${TS}"
info "Backup: ${ENV_FILE}.bak.${TS}"

gen(){ openssl rand -hex 24; }

# KEY in der .env ersetzen (oder anhängen), ohne die Datei neu zu schreiben
set_env(){
  local k="$1" v="$2"
  if grep -q "^${k}=" "$ENV_FILE"; then
    # | als Trenner, damit v keine sed-Sonderzeichen braucht (hex ist ohnehin sicher)
    sed -i "s|^${k}=.*|${k}=${v}|" "$ENV_FILE"
  else
    echo "${k}=${v}" >> "$ENV_FILE"
  fi
}

# rpcauth-Tripel erzeugen: "user|klartext-pass|user:salt$hmac" (wie gen_secrets.sh)
gen_rpcauth(){
  local user="$1" pass salt hmac
  pass="$(openssl rand -hex 24)"
  salt="$(openssl rand -hex 16)"
  hmac="$(printf '%s' "$pass" | openssl dgst -sha256 -hmac "$salt" | sed 's/^.* //')"
  printf '%s|%s|%s:%s$%s' "$user" "$pass" "$user" "$salt" "$hmac"
}


#NATS-Identitäten, Operator-Token, ntfy-Token
info "Rotiere NATS-Passwörter, OPERATOR_TOKEN, NTFY_TOKEN"
set_env MW_NATS_PASS       "n$(gen)"
set_env TXB_NATS_PASS      "n$(gen)"
set_env OPERATOR_NATS_PASS "n$(gen)"
set_env SETUP_NATS_PASS    "n$(gen)"
set_env NTFY_TOKEN         "$(gen)"


# 2. Datenbank-Passwörter – erst LIVE per ALTER, dann in .env schreiben
NEW_MW_DB_PASSWORD="$(gen)"
NEW_PG_PASSWORD="$(gen)"

if docker compose -f "$COMPOSE" ps --status running postgres | grep -q postgres; then
  info "Setze DB-Passwörter live (mw_app + Superuser)"
  docker compose -f "$COMPOSE" exec -T postgres \
    psql -v ON_ERROR_STOP=1 -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" <<SQL
ALTER ROLE "${MW_DB_USER}" WITH PASSWORD '${NEW_MW_DB_PASSWORD}';
ALTER USER "${POSTGRES_USER}" WITH PASSWORD '${NEW_PG_PASSWORD}';
SQL
else
  info "postgres läuft nicht – ALTER übersprungen (nur .env wird gesetzt)"
fi

set_env MW_DB_PASSWORD  "$NEW_MW_DB_PASSWORD"
set_env POSTGRES_PASSWORD "$NEW_PG_PASSWORD"


#btc-core RPC (rpcauth.conf-Hashes + Klartext-Client-Creds in .env)
info "Rotiere btc-core rpcauth (middleware + txbuilder)"
IFS='|' read -r MW_USER  MW_PASS  MW_AUTH  <<< "$(gen_rpcauth middleware)"
IFS='|' read -r TXB_USER TXB_PASS TXB_AUTH <<< "$(gen_rpcauth txbuilder)"

{
  echo "rpcauth=${MW_AUTH}"
  echo "rpcauth=${TXB_AUTH}"
} > "$RPCAUTH_FILE"
chmod 644 "$RPCAUTH_FILE"

set_env BTC_RPC_USER_MW  "$MW_USER"
set_env BTC_RPC_PASS_MW  "$MW_PASS"
set_env BTC_RPC_USER_TXB "$TXB_USER"
set_env BTC_RPC_PASS_TXB "$TXB_PASS"

chmod 600 "$ENV_FILE"


#Container neu erzeugen
if [[ "${NO_RESTART:-0}" != "1" ]]; then
  info "Container neu erzeugen (nats, btc-core, postgres, middleware, tx-builder)"
  docker compose -f "$COMPOSE" up -d --force-recreate --no-deps \
    nats btc-core postgres middleware tx-builder
else
  info "NO_RESTART=1 -> Neustart übersprungen. Manuell:"
  echo "    docker compose up -d --force-recreate nats btc-core postgres middleware tx-builder"
fi

echo
info "Fertig. Rotiert: NATS x4, OPERATOR_TOKEN, NTFY_TOKEN, mw_app-PW, Superuser-PW, rpcauth (mw/txb)."
echo
echo "  !!! HMAC-Secret wurde NICHT rotiert !!!"
echo "  Es liegt synchron auf Middleware UND Signer-VM. Rotation nur über den USB-Weg:"
echo "    1) Signer-VM:  wgHMAC_export.sh  (neues HMAC.secret aufs USB-Medium)"
echo "    2) Hot-System: wgHMAC_import.sh  (Secret nach middleware_data/secrets/ übernehmen)"
echo "    3) middleware neu erzeugen:  docker compose up -d --force-recreate middleware"
echo "  Beide Seiten müssen im selben Schritt getauscht werden, sonst 401 an der Signer-API."
