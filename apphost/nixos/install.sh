#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NIX_FLAGS=(--extra-experimental-features "nix-command flakes")

# Ein bisschen Farbe tut dem ganzen ja nicht weh. 
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' B='\033[0;34m' N='\033[0m'
info()  { echo -e "${G}▶${N}  $*"; }
warn()  { echo -e "${Y}⚠${N}  $*"; }
err()   { echo -e "${R}✖${N}  $*" >&2; exit 1; }

# Vorbedingungen
[[ $EUID -ne 0 ]] && err "Bitte als root ausführen: sudo bash nixos/install.sh"
[[ -f "$REPO_DIR/flake.nix" ]] || err "Kein Repo-Root gefunden (flake.nix fehlt in $REPO_DIR)"

cd "$REPO_DIR"

echo ""
echo "  Repo:    $REPO_DIR"
echo "  Dieses Skript:"
echo "  - partitioniert eine Festplatte (GPT + EFI + Swap + Btrfs)"
echo "  - installiert NixOS mit der AppHost-Hochsicherheitskonfiguration"
echo "  - legt den AppHost-Stack unter /opt/apphost bereit"
echo ""

echo ""
echo "  Bitte wählen Sie ein sicheres Passwort für Ihren Nutzer."
echo "  Dieses Passwort wird für 'sudo' benötigt (zweiter Faktor nach SSH-Key)."
echo ""

if [[ $# -ge 3 ]]; then
  HASHED_PASSWORD="$3"
  info "Passwort-Hash Argument gesetzt, überspringe."
else
  while true; do
    read -rsp "  Passwort: " PW1; echo ""
    read -rsp "  Passwort bestätigen: " PW2; echo ""
    [[ "$PW1" == "$PW2" ]] && break
    warn "Passwörter stimmen nicht überein. Bitte erneut eingeben."
  done
  HASHED_PASSWORD="$(printf '%s' "$PW1" | nix run "${NIX_FLAGS[@]}" nixpkgs#mkpasswd -- -m sha-512 -s)"
  unset PW1 PW2
fi

echo "Passwort-Hash erzeugt"

echo ""
warn "WARNUNG: ALLE DATEN auf der Festplatte werden UNWIDERRUFLICH GELÖSCHT!"
echo ""
read -rp "  Bitte 'ja' eingeben um fortzufahren: " CONFIRM
[[ "$CONFIRM" == "ja" ]] || { echo ""; info "Abgebrochen."; exit 0; }

info "Schreibe Passwort-Hash nach /mnt/etc/apphost-password-hash (außerhalb des Repos)..."
# Wird erst nach disko geschriebe. Merker für später:
APPHOST_PW_HASH="$HASHED_PASSWORD"

# hardware-configuration.nix Platzhalter (wird eh überschrieben)
info "Erstelle hardware-configuration.nix Platzhalter..."
cat > nixos/hardware-configuration.nix << 'NIXEOF'
{ modulesPath, ... }:
{ imports = [ (modulesPath + "/installer/scan/not-detected.nix") ]; }
NIXEOF

# Festplattenverschlüsselung
echo ""
echo "  Optional kann die Root-Partition zusätzlich mit LUKS2 verschlüsselt werden."
echo "  Achtung: Danach wird bei JEDEM Boot eine Passphrase über die Server-Konsole benötigt"
echo "  > Kein unbeaufsichtigter Neustart, kein Boot ohne Konsolenzugriff (z.B. über die Proxmox-Konsole)."
echo ""
read -rp "  Festplattenverschlüsselung aktivieren? [j/N]: " ENC_ANSWER
if [[ "$ENC_ANSWER" =~ ^[jJyY] ]]; then
  DISK_ENCRYPTION=true
  warn "Festplattenverschlüsselung aktiviert. Die Passphrase wird gleich bei der Formatierung festgelegt."
else
  DISK_ENCRYPTION=false
  info "Festplattenverschlüsselung deaktiviert (Standard)."
fi

cat > "$REPO_DIR/nixos/disk-encryption.nix" << NIXEOF
# Automatisch von nixos/install.sh gesetzt. Manuelles Umschalten nur vo einer Neuinstallation sinnvoll
$DISK_ENCRYPTION
NIXEOF

SSH_KEY_REGEX='^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com) [A-Za-z0-9+/]+=*( .*)?$'
if [[ $# -ge 4 ]]; then
  SSH_PUBKEY="$4"
  info "SSH Public Key Argument gesetzt, überspringe."
else
  while true; do
    read -rp "  SSH Public Key: " SSH_PUBKEY
    [[ "$SSH_PUBKEY" =~ $SSH_KEY_REGEX ]] && break
    warn "Das sieht nicht wie ein gültiger SSH Public Key aus (muss z. B. mit 'ssh-ed25519 ' oder einem anderen gängigen key-format beginnen). Bitte erneut eingeben."
  done
fi

cat > "$REPO_DIR/nixos/ssh-key.nix" << NIXEOF
# Automatisch von nixos/install.sh gesetzt. Nachträglich änderbar durch Bearbeiten dieser Datei und anschließendes:
# >  sudo nixos-rebuild switch --flake /opt/apphost#apphost
[
  "$SSH_PUBKEY"
]
NIXEOF

info "SSH Public Key gespeichert"

# disko Partitionierung
info "Starte disko (Partitionierung + Btrfs-Formatierung)..."
nix run "${NIX_FLAGS[@]}" github:nix-community/disko \
  -- --mode disko "$REPO_DIR/nixos/disko.nix"

info "Festplatte partitioniert und unter /mnt gemountet"

# Passwort-Hash in Datei auf dem Zielsystem schreiben
mkdir -p /mnt/etc
printf '%s' "$APPHOST_PW_HASH" > /mnt/etc/apphost-password-hash
chmod 600 /mnt/etc/apphost-password-hash
info "Passwort-Hash nach /mnt/etc/apphost-password-hash geschrieben"

# fileSystems, swapDevices und boot.initrd.luks.devices werden von disko deklarativ
# verwaltet und dürfen nicht in hardware-configuration.nix auftauchen (Konflikte -.-).
# Letzteres detektiert nixos-generate-config, weil disko den LUKS-Container beim
# Formatieren bereits geöffnet hat (per by-uuid statt disko's by-partlabel).
info "Generiere nixos/hardware-configuration.nix..."
nixos-generate-config \
  --root /mnt \
  --show-hardware-config \
  | awk '
      /^  fileSystems\./          { skip = 1 }
      skip && /^    \};/          { skip = 0; next }
      skip                        { next }
      /^  swapDevices /           { next }
      /^  boot\.initrd\.luks\.devices\./ { next }
      { print }
    ' > nixos/hardware-configuration.nix

info "hardware-configuration.nix generiert"

# ---- NixOS installieren ----
# Wichtig: Flake aus $REPO_DIR evaluieren (außerhalb von /mnt).
# Wäre die Quelle innerhalb von /mnt (dem --store-Ziel), schlägt Nix mit
# einem NAR-Hash-Assertion-Fehler fehl, weil Quelle und Ziel-Store kollidieren.
info "Starte nixos-install ohne Bootloader (dieser Vorgang wird einen Moment dauern)..."
# --no-bootloader: lanzaboote braucht Secure-Boot-Schlüssel zum Signieren,
# die noch nicht existieren. Wir erstellen sie danach und installieren den Bootloader separat.
nixos-install \
  --root /mnt \
  --flake "path:$REPO_DIR#apphost" \
  --no-root-passwd \
  --no-bootloader \
  --option extra-experimental-features "nix-command flakes"

echo "NixOS erfolgreich installiert! :party:"

# SecureBoot magie
# lanzaboote erwartet Schlüssel unter {pkiBundle}/keys/ = /etc/secureboot/keys/
# sbctl nutzt seinen internen State-Dir (/usr/share/secureboot oder Config).
# Wir schreiben dahereine sbctl-Config, die auf /etc/secureboot zeigt, bevor wir create-keys rufen.
echo "Generiere Secure Boot Schlüssel..."
nixos-enter --root /mnt -- bash -c '
  set -euo pipefail
  TARGET=/etc/secureboot/keys
  mkdir -p "$TARGET" /etc/sbctl

  SBCTL_CFG=/etc/sbctl/configuration.json
  [ -f "$SBCTL_CFG" ] || printf '"'"'{"db_path":"/etc/secureboot"}'"'"' > "$SBCTL_CFG"

  sbctl create-keys

  # Falls sbctl die Config ignoriert hat und Keys woanders liegen -> kopieren
  if [ ! -f "$TARGET/db/db.pem" ]; then
    for src in /usr/share/secureboot /etc/secureboot; do
      if [ -f "$src/keys/db/db.pem" ]; then
        cp -r "$src/keys/." "$TARGET/"
        echo "Keys von $src/keys nach $TARGET kopiert"
        break
      fi
    done
  fi

  [ -f "$TARGET/db/db.pem" ] || { echo "FEHLER: Secure Boot Keys nicht gefunden! Das sollte nicht passieren."; exit 1; }
  echo "Keys erfolgreich unter $TARGET"
' && info "Secure Boot Schlüssel erzeugt: /etc/secureboot" \
  || warn "sbctl fehlgeschlagen – nach dem Neustart manuell: sudo sbctl create-keys && sudo nixos-rebuild boot"

# ---- Bootloader installieren ----
info "Installiere Bootloader (lanzaboote signiert EFI-Binaries)..."
if nixos-enter --root /mnt -- /nix/var/nix/profiles/system/bin/switch-to-configuration boot; then
  info "Bootloader installiert"
else
  warn "Bootloader-Installation fehlgeschlagen – nach dem Neustart manuell:"
  warn "  sudo nixos-rebuild boot --flake /opt/apphost#apphost"
fi

MONOREPO_ROOT="$(git -C "$REPO_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
MONOREPO_REMOTE=""
[[ -n "$MONOREPO_ROOT" ]] && MONOREPO_REMOTE="$(git -C "$MONOREPO_ROOT" remote get-url origin 2>/dev/null || true)"

if [[ -n "$MONOREPO_REMOTE" ]]; then
  MONOREPO_BRANCH="$(git -C "$MONOREPO_ROOT" rev-parse --abbrev-ref HEAD)"
  APPHOST_SUBDIR="$(realpath --relative-to="$MONOREPO_ROOT" "$REPO_DIR")"
  CHECKOUT_DIR="/mnt/opt/.monorepo"

  info "Richte aktualisierbares Git-Repo unter /opt ein (Sparse-Checkout: $APPHOST_SUBDIR)..."
  mkdir -p /mnt/opt
  git clone --no-checkout --branch "$MONOREPO_BRANCH" "$MONOREPO_ROOT" "$CHECKOUT_DIR"
  git -C "$CHECKOUT_DIR" remote set-url origin "$MONOREPO_REMOTE"
  git -C "$CHECKOUT_DIR" sparse-checkout init --cone
  git -C "$CHECKOUT_DIR" sparse-checkout set "$APPHOST_SUBDIR"
  git -C "$CHECKOUT_DIR" checkout "$MONOREPO_BRANCH"
  ln -s "$CHECKOUT_DIR/$APPHOST_SUBDIR" /mnt/opt/apphost

  # Maschinenspezifische Dateien sind gitignored (siehe .gitignore) und daher nach dem
  # Sparse-Checkout nicht vorhanden – aus $REPO_DIR nachziehen, wo sie in diesem Lauf
  # gerade frisch erzeugt wurden.
  for f in nixos/hardware-configuration.nix nixos/ssh-key.nix nixos/disk-encryption.nix; do
    cp "$REPO_DIR/$f" "/mnt/opt/apphost/$f"
  done
else
  warn "Kein Git-Remote unter $REPO_DIR gefunden. Wurde die Ursprungskopie heruntergeladen und nicht geklont? Kopiere Repo ohne Versionierung (kein 'git pull' auf dem Server möglich)."
  mkdir -p /mnt/opt/apphost
  cp -r "$REPO_DIR"/. /mnt/opt/apphost
fi

# .env konfigurieren
echo ""
echo -e "  ${B}Konfiguration${N}"
echo -e "  MQTT- und Ntfy-Passwörter werden automatisch generiert."
echo -e "  Alle Werte können nach dem Neustart in /opt/apphost/.env geändert werden."
echo ""

_prompt() {
    local label="$1" default="${2:-}" silent="${3:-}"
    local val
    if [[ "$silent" == "secret" ]]; then
        read -rsp "  ${label}: " val; echo "" >&2
    else
        if [[ -n "$default" ]]; then
            read -rp "  ${label} [${default}]: " val
            val="${val:-$default}"
        else
            read -rp "  ${label}: " val
        fi
    fi
    printf '%s' "$val"
}

ENV_DOMAIN=""
while [[ -z "$ENV_DOMAIN" ]]; do
    ENV_DOMAIN=$(_prompt "Domain (z.B. example.com)")
done

ENV_ACME_EMAIL=""
while [[ -z "$ENV_ACME_EMAIL" ]]; do
    ENV_ACME_EMAIL=$(_prompt "ACME E-Mail (Let's Encrypt)")
done

ENV_CF_TOKEN=""
while [[ -z "$ENV_CF_TOKEN" ]]; do
    ENV_CF_TOKEN=$(_prompt "Cloudflare API Token" "" secret)
done

ENV_AUTH_USER=$(_prompt "Authelia Admin-Nutzer" "admin")
ENV_AUTH_EMAIL=$(_prompt "Authelia Admin-E-Mail" "$ENV_ACME_EMAIL")

ENV_AUTH_PW=""
while true; do
    ENV_AUTH_PW=$(_prompt  "Authelia Admin-Passwort" "" secret)
    ENV_AUTH_PW2=$(_prompt "Authelia Admin-Passwort (bestätigen)" "" secret)
    [[ "$ENV_AUTH_PW" == "$ENV_AUTH_PW2" ]] && break
    warn "Passwörter stimmen nicht überein."
done
unset ENV_AUTH_PW2

# Zufällige Passwörter für MQTT und Ntfy
# openssl ist auf dem Live-ISO nicht vorinstalliert, daher wie mkpasswd via nix run.
_randhex() { nix run "${NIX_FLAGS[@]}" nixpkgs#openssl -- rand -hex 16; }
ENV_MQTT_HA="$(_randhex)"
ENV_MQTT_Z2M="$(_randhex)"
ENV_MQTT_ESP="$(_randhex)"
ENV_MQTT_RO="$(_randhex)"
ENV_NTFY_ADMIN="$(_randhex)"
ENV_NTFY_ALERT="$(_randhex)"

ENV_FILE="/mnt/opt/apphost/.env"
cp "/mnt/opt/apphost/.env.example" "$ENV_FILE"
chmod 600 "$ENV_FILE"

# Werte in .env eintragen (Python für sicheres Escaping beliebiger Zeichen)
# python3 ist auf dem Live-ISO nicht vorinstalliert, daher wie openssl/mkpasswd via nix run.
nix run "${NIX_FLAGS[@]}" nixpkgs#python3 -- - "$ENV_FILE" \
    "$ENV_DOMAIN" "$ENV_ACME_EMAIL" "$ENV_CF_TOKEN" \
    "$ENV_AUTH_USER" "$ENV_AUTH_EMAIL" "$ENV_AUTH_PW" \
    "$ENV_MQTT_HA" "$ENV_MQTT_Z2M" "$ENV_MQTT_ESP" "$ENV_MQTT_RO" \
    "$ENV_NTFY_ADMIN" "$ENV_NTFY_ALERT" << 'PYEOF'
import re, sys
env_file = sys.argv[1]
keys = [
    'DOMAIN', 'ACME_EMAIL', 'CF_DNS_API_TOKEN',
    'AUTHELIA_ADMIN_USER', 'AUTHELIA_ADMIN_EMAIL', 'AUTHELIA_ADMIN_PASSWORD',
    'MQTT_HOMEASSISTANT_PASSWORD', 'MQTT_ZIGBEE2MQTT_PASSWORD',
    'MQTT_ESPHOME_PASSWORD', 'MQTT_READONLY_PASSWORD',
    'NTFY_ADMIN_PASSWORD', 'NTFY_ALERTMANAGER_PASSWORD',
]
with open(env_file) as f:
    content = f.read()
for key, value in zip(keys, sys.argv[2:]):
    pattern = rf'^({re.escape(key)}=).*'
    new, n = re.subn(pattern, lambda m: m.group(1) + value, content, flags=re.MULTILINE)
    content = new if n else content + f'\n{key}={value}'
with open(env_file, 'w') as f:
    f.write(content)
PYEOF

unset ENV_AUTH_PW ENV_CF_TOKEN
info ".env konfiguriert"

# Secrets generieren (läuft im Live-System, nix ist verfügbar)
info "Generiere Secrets (lädt benötigte Nix-Pakete, dauert einen Moment...)"
cd /mnt/opt/apphost

for script in update-secrets-authelia update-secrets-mosquitto update-secrets-ntfy; do
    if bash "scripts/${script}.sh"; then
        info "${script} ✓"
    else
        warn "${script} fehlgeschlagen – nach Neustart manuell ausführen:"
        warn "  bash /opt/apphost/scripts/${script}.sh"
    fi
done

cd "$REPO_DIR"

echo ""
echo -e "${G}NixOS-Installation erfolgreich abgeschlossen!${N}"
echo ""
echo -e "  ${B}Nach dem Neustart:${N}"
echo ""
echo -e "  ${B}1.${N} SSH-Login:     ssh apphost@<IP-ADRESSE>"
echo -e "  ${B}2.${N} Stack starten: cd /opt/apphost && docker compose up -d"
echo -e "  ${B}3.${N} Tor-Adresse:   bash /opt/apphost/scripts/show-onion-address.sh"
echo -e "            TOR_DOMAIN in .env eintragen, danach: docker compose up -d"
echo ""

for i in 5 4 3 2 1; do
  echo -ne "\r  ${Y}Neustart in ${i} Sekunden … (Strg+C zum Abbrechen)${N}  "
  sleep 1
done
echo ""
reboot now
