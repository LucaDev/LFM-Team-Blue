# Runbook (Markdown): Pub‑Key‑Generierung & Verteilung (Air‑gapped) + Proxmox „USB‑Stecken“

> Ziel: **Signer** erzeugt offline einen **GPG‑Approval‑Key** (Private Key bleibt auf dem Signer).  
> Alle anderen Systeme (**keyB, keyC, hot**) bekommen **nur den Public Key** (für `gpg --verify`).  
> **Proxmox Host** macht ausschließlich das „physische Einstecken“ (attach/detach der virtuellen USB‑Disk).  
> **Kein Hash‑Austausch** mit der Hot Wallet nötig, wenn Hot als **KeyA** signiert (Signatur reicht als Integritäts-/Authentizitätsnachweis).

***

## 0) Begriffe & Maschinen (sehr wichtig fürs Debugging)

### Proxmox Host

*   Führt `/root/psbt-usbFlow.sh` aus
*   **Attacht/Detacht** das USB‑qcow2 als `scsi2` an genau **eine** VM
*   Startet VM falls nötig

### VMs

*   **signer** (offline, keyless für Bitcoin, aber **hat GPG Private Key** für Approvals)
*   **keyB / keyC** (offline, halten Bitcoin‑Keys; bekommen **Signer Public Key** zum Verifizieren)
*   **hot** (online, Bitcoin Core; bekommt **Signer Public Key** optional zum Verifizieren von `final.psbt.sig`)

### Wechselmedium (USB‑Medium)

*   Label in deiner Notiz: **`USB`**
*   Mountpoint: **`/mnt/usb`**

> **Achtung**: `mkfs.ext4` löscht den Datenträger. Das ist **nur beim initialen Setup** korrekt.

Es gibt nur ein USB-Medium auf dem immer nur eine TX gespeichert ist.
Dementsprechend sind beide objekte gleichzusetzen und Synonym zu verwenden

***

## 1) Voraussetzungen (einmalig)

### 1.1 Mountpoint deklarativ (NixOS base.nix)

```nix
systemd.tmpfiles.rules = [
  "d /mnt/usb 0755 root root - -"
  "d /var/lib/psbt-guard 0700 root root - -"
  "d /var/lib/psbt-guard/gnupg 0700 root root - -"
  "d /var/lib/psbt-guard/identity 0700 root root - -"
];
```

### 1.2 Proxmox Script vorhanden & korrekt aufrufbar

Auf dem **Proxmox Host**:

*   Script liegt unter `/root/psbt-usbFlow.sh`
*   ist ausführbar:

```bash
chmod +x /root/psbt-usbFlow.sh
```

***

## 2) Ziel‑Artefakte / erwartete Dateien

### Auf dem USB‑Medium (Label `USB`)

Wir legen (empfohlen) folgende Struktur an:

```text
/mnt/usb/psbt/identity/
  signer-pubkey.asc
  signer-identity.txt
```

### Lokal auf den VMs (State)

*   Signer GPG State, dieser Ort wird von allen GPG-Operationen verwendet:
    *   `/var/lib/psbt-guard/gnupg/`
*   Signer Public Key Export (lokal):
    *   `/var/lib/psbt-guard/identity/signer-pubkey.asc`
    *   `/var/lib/psbt-guard/identity/signer-identity.txt`

***

## 3) Workflow: Pub Key Generation + Distribution

> **Jeder „/root/psbt-usbFlow.sh …“ Schritt wird auf dem Proxmox Host ausgeführt.**  
> Innerhalb der VM ausführen der `mount` + Script‑Kommandos.

***

### Schritt 1 — (Proxmox Host) „USB in Signer stecken“

**Auf dem Proxmox Host:**

```bash
/root/psbt-usbFlow.sh signer
```

**Was passiert (Host‑seitig):**

*   prüft ob VM läuft → startet ggf.
*   attacht `psbt-usb.qcow2` als `scsi2`
*   wartet auf ENTER
*   detacht danach

**Debug‑Hinweise (Host):**

*   Wenn Attach fehlschlägt:
    *   VM läuft nicht → Script sollte `qm start` machen
    *   `scsi2` belegt → `qm config <vmid>` prüfen

***

### Schritt 1a — (Signer VM) Medium initialisieren (nur einmal!) + mounten

> **Nur beim ersten Mal** (oder beim bewussten erneuten Formatieren).

```bash
lsblk
```

**Erwartete Ausgabe (Beispiel):**

*   `sda` = Systemdisk
*   `sdb` / `sdb1` = USB‑Disk (die vom Proxmox Host attached wurde)

**⚠️ Nur wenn du sicher bist, dass `/dev/sdb1` das USB ist:**

```bash
sudo mkfs.ext4 -L USB /dev/sdb1
```

Danach mounten:

```bash
sudo mount /dev/disk/by-label/USB /mnt/usb
```

***

### Schritt 1b — (Signer VM) Public Key erzeugen: `hash-keyGen.sh`

**Auf der Signer‑VM (Medium ist gemountet):**

```bash
sudo hash-keyGen.sh
```

**Automatisierte Schritte:**

*   sicherstellen: airgapped (keine NIC UP außer `lo`)
*   erzeugt **GPG Keypair** im Signer‑State (z. B. `GNUPGHOME=/var/lib/psbt-guard/gnupg`)
*   exportiert **Public Key + Metadaten**
*   schreibt diese nach USB (`psbt/identity/...`)
*   zeigt Dir 40 hexadezimale Zeichen als Fingerprint
    *   Schriebe diese ab für einen späteren vergleich
*   `sync`
*   `umount`

**Erwartete Outputs (Dateien):**

*   auf USB:
    *   `/mnt/usb/psbt/identity/signer-pubkey.asc`
    *   `/mnt/usb/psbt/identity/signer-identity.txt`
*   lokal (Signer):
    *   `/var/lib/psbt-guard/gnupg/` (private key material)
    *   `/var/lib/psbt-guard/identity/...`

### Schritt 1c — (Signer VM) Revocation erzeugen

```bash
export GNUPGHOME=/var/lib/psbt-guard/gnupg
mkdir -p /var/lib/psbt-guard/identity
chmod 0700 /var/lib/psbt-guard/identity

gpg --output /var/lib/psbt-guard/identity/signer-revocation.asc --gen-revoke <FINGERPRINT>
chmod 0400 /var/lib/psbt-guard/identity/signer-revocation.asc
```

***

## Schritt 2 — (Proxmox Host) „USB in KeyB stecken“

**Auf dem Proxmox Host:**

```bash
/root/psbt-usbFlow.sh keyb
```

***

### Schritt 2a — (KeyB VM) mount + PubKey importieren/storen: `hash-keyStore.sh`

**Auf der KeyB‑VM:**

```bash
sudo mount /dev/disk/by-label/USB /mnt/usb
sudo hash-keyStore.sh
```

**Automatisierte Schritte:**

*   airgap check
*   prüft, dass **Signer Public Key** auf USB existiert:
    *   `/mnt/usb/psbt/identity/signer-pubkey.asc`
*   importiert Signer Public Key ins lokale KeyB‑GNUPG:
    *   `GNUPGHOME=/var/lib/psbt-guard/gnupg`
    *   `gpg --import ...`
*   `sync`
*   `umount`

**Erwartete Outputs (Dateien):**

*   **lokal auf KeyB**:
    *   `/var/lib/psbt-guard/gnupg/pubring.kbx` (enthält Signer PubKey)

***

## Schritt 3 — (Proxmox Host) „USB in KeyC stecken“

Wdh. von Schritt 2 mit

```bash
/root/psbt-usbFlow.sh keyc
```

***

# Keys kompromittiert

## Key revocation
Die public Keys müssen daraufhin revoked werden, was über den import einer Datei möglich ist
Diese wird auf Singer-VM mit dem private Key erstellt.

Auf dem private-Hash-Holder (signer):
```bash
export GNUPGHOME=/var/lib/psbt-guard/gnupg

# Fingerprint bestimmen
export GNUPGHOME=/var/lib/psbt-guard/gnupg
gpg --list-secret-keys --keyid-format long

FP="<DEIN_FINGERPRINT>"

mkdir -p /var/lib/psbt-guard/identity
chmod 0700 /var/lib/psbt-guard/identity

gpg --output /var/lib/psbt-guard/identity/signer-revocation.asc --gen-revoke "$FP"
chmod 0400 /mnt/usb/psbt/identity/signer-revocation.asc
```

Auf Public-Hash-Holder B und C
```bash
export GNUPGHOME=/var/lib/psbt-guard/gnupg
gpg --import /mnt/usb/psbt/identity/signer-revocation.asc
```
Revoked status prüfen per
```bash
gpg --list-keys --with-colons | grep -E '^(pub|rev):'
gpg --list-keys --fingerprint
```

## Key Deletion
Anstelle von Revoke können diese auch direkt gelöscht werden.
Den einzigen Vorteil weißt revoke durch seine Nachverfolgbarkeit aus.

Auf dem private-Hash-Holder (signer):
```bash
rm -rf /var/lib/psbt-guard/gnupg

#Ordner neu-Anlegen
mkdir -p /var/lib/psbt-guard/gnupg
chmod 0700 /var/lib/psbt-guard/gnupg
```
Prüfen per:
```bash
gpg --list-secret-keys
gpg --list-keys
```

Auf Public-Hash-Holder B und C
```bash
rm -rf /var/lib/psbt-guard/gnupg

#Ordner neu-Anlegen
mkdir -p /var/lib/psbt-guard/gnupg
chmod 0700 /var/lib/psbt-guard/gnupg
```
Prüfen per:
```bash
gpg --list-keys
```

# Hash‑verify

## Zweck

`hash-verify.sh` wird im **PSBT‑Workflow** als Signatur-Verifizierer verwendet, um **vor kritischen Schritten** sicherzustellen, dass die Datei **vom Signer freigegeben** wurde.


Technisch passiert das über **GPG-Signaturprüfung**:

*   die GPG‑Signatur von `approval.json` und die darin gebundene SHA256‑Hash‑Referenz auf `appr.<id>.psbt`



> **Warum reicht das als „Hash‑Verify“?**  
> Wir verifizieren die Signatur auf approval.json und prüfen, dass die freigegebene PSBT (appr.<id>.psbt) dem in approval.json gebundenen SHA256 entspricht.

***

## Einbindung in den Workflow (wo genau ausführen?)

### **Auf KeyB/KeyC (bevor in Sparrow signiert wird)**

**Erwartete Dokumente auf dem USB:**

*   `psbt/appr.<id>.psbt`
*   `psbt/auth/approval.json`
*   `psbt/auth/approval.json.sig`


**VM (KeyB/KeyC):**

```bash
sudo mount /dev/disk/by-label/USB /mnt/usb
sudo hash-verify.sh
```

**Erwartete Ausgabe:**

*   `OK: Approved vom Signer. Du darfst jetzt in Sparrow signieren …`

Daraufhin kann die psbt in Sparrow importiert, signiert und exportiert werden

***

## Typische Debug‑Checks (wenn `hash-verify.sh` fehlschlägt)

### 1) Ist der Signer‑Public‑Key importiert?

In der jeweiligen VM:

```bash
export GNUPGHOME=/var/lib/psbt-guard/gnupg
gpg --list-keys
```

### 2) Sind die Dateien da?

```bash
ls -lah /mnt/usb/psbt/
```

### 3) Fingerprint manuell prüfen (für genaue Fehlermeldung)

```bash
export GNUPGHOME=/var/lib/psbt-guard/gnupg
gpg --verify /mnt/usb/psbt/auth/approval.json.sig /mnt/usb/psbt/auth/approval.json
sha256sum /mnt/usb/psbt/appr.<id>.psbt
```

***

## Kein Key-Austausch zwischen Hot und Cold Wallet

Spätere Verifizierung nicht benötigt, da beim initialen Hot -> Cold eine psbt übertragen wird, die bereits von keyA signiert wurde.
Dies kann verifiziert werden und ein weiterer Hash würde redundanz bedeuten.

Auch ist ein weiterer hash von Cold -> Hot vernachlässigbar, da die Hot Wallet nur noch den USB inhalt broadcasted.
Fehlerhafte, unsignierte, manipuliert TXs würde beim broadcast fehlschlagen oder könnten das cold Wallet nicht addressieren

Zudem soll der USB Flashdrive immernur für eine TX zur selben Zeit verwendet werden


###USB setup 
go to VM
Hardware
Add Hard Disc
Schriebe auf dieser
unmount
klick auf edit -> detach
cklick auf disk action -> Reassign Owner 
    zum nächsten