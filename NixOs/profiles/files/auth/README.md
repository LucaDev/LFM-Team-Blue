# Runbook (Markdown): Pub‑Key‑Generierung & Verteilung (Air‑gapped) + Proxmox „USB‑Stecken“

> Ziel: **Signer** erzeugt offline einen **GPG‑Approval‑Key** (Private Key bleibt auf dem Signer).  
> Alle anderen Systeme (**keyB, keyC, hot**) bekommen **nur den Public Key** (für `gpg --verify`).  
> **Proxmox Host** macht ausschließlich das „physische Einstecken“ (attach/detach der virtuellen USB‑Disk).  
> **Kein Hash‑Austausch** mit der Hot Wallet nötig, wenn Hot als **KeyA** signiert (Signatur reicht als Integritäts-/Authentizitätsnachweis).

***

## 0) Begriffe & Maschinen (sehr wichtig fürs Debugging)

### Proxmox Host

*   Führt `/root/psbt-usb.sh` aus
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

*   Script liegt unter `/root/psbt-usb.sh`
*   ist ausführbar:

```bash
chmod +x /root/psbt-usb.sh
```

***

## 2) Ziel‑Artefakte / erwartete Dateien

### Auf dem USB‑Medium (Label `USB`)

Wir legen (empfohlen) folgende Struktur an:

```text
/mnt/usb/psbt/identity/
  signer/
    signer-pubkey.asc
    signer-identity.txt
  manifest.sha256 (optional)
```

### Lokal auf den VMs (State)

*   Signer GPG State, dieser Ort wird von allen GPG-Operationen verwendet:
    *   `/var/lib/psbt-guard/gnupg/`
*   Signer Public Key Export (lokal):
    *   `/var/lib/psbt-guard/identity/signer-pubkey.asc`
    *   `/var/lib/psbt-guard/identity/signer-identity.txt`

***

## 3) Workflow: Pub Key Generation + Distribution

> **Jeder „/root/psbt-usb.sh …“ Schritt wird auf dem Proxmox Host ausgeführt.**  
> Innerhalb der VM ausführen der `mount` + Script‑Kommandos.

***

### Schritt 1 — (Proxmox Host) „USB in Signer stecken“

**Auf dem Proxmox Host:**

```bash
/root/psbt-usb.sh signer
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
*   schreibt diese nach USB (z. B. `psbt/identity/signer/...`)
*   `sync`
*   `umount`

**Erwartete Outputs (Dateien):**

*   auf USB:
    *   `/mnt/usb/psbt/identity/signer/signer-pubkey.asc`
    *   `/mnt/usb/psbt/identity/signer/signer-identity.txt`
*   lokal (Signer):
    *   `/var/lib/psbt-guard/gnupg/` (private key material)
    *   `/var/lib/psbt-guard/identity/...`

***

## Schritt 2 — (Proxmox Host) „USB in KeyB stecken“

**Auf dem Proxmox Host:**

```bash
/root/psbt-usb.sh keyb
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
    *   `/mnt/usb/psbt/identity/signer/signer-pubkey.asc`
*   importiert Signer Public Key ins lokale KeyB‑GNUPG:
    *   `GNUPGHOME=/var/lib/psbt-guard/gnupg`
    *   `gpg --import ...`
*   schreibt Import‑Status/Manifest
*   `sync`
*   `umount`

**Erwartete Outputs (Dateien):**

*   **lokal auf KeyB**:
    *   `/var/lib/psbt-guard/gnupg/pubring.kbx` (enthält Signer PubKey)

***

## Schritt 3 — (Proxmox Host) „USB in KeyC stecken“

Wdh. von Schritt 2 mit

```bash
/root/psbt-usb.sh keyc
```

***

# Hash‑verify

## Zweck

`hash-verify.sh` wird im **PSBT‑Workflow** als Signatur-Verifizierer verwendet, um **vor kritischen Schritten** sicherzustellen, dass die Datei **vom Signer freigegeben** wurde.


Technisch passiert das über **GPG-Signaturprüfung**:

*   Key‑VMs verifizieren: `for-signing.psbt.sig` ↔ `for-signing.psbt`


> **Warum reicht das als „Hash‑Verify“?**  
> Weil die Signaturprüfung intern den Hash der Datei berechnet und mit der Signatur vergleicht. Ein separater Hash‑Austausch ist redundant.

***

## Einbindung in den Workflow (wo genau ausführen?)

### **Auf KeyB/KeyC (bevor in Sparrow signiert wird)**

**Erwartete Dokumente auf dem USB:**

*   `psbt/out/for-signing.psbt`
*   `psbt/out/for-signing.psbt.sig`

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
ls -lah /mnt/usb/psbt/out/
```

### 3) Signatur manuell prüfen (für genaue Fehlermeldung)

```bash
export GNUPGHOME=/var/lib/psbt-guard/gnupg
gpg --verify /mnt/usb/psbt/out/for-signing.psbt.sig /mnt/usb/psbt/out/for-signing.psbt
# oder:
gpg --verify /mnt/usb/psbt/out/final.psbt.sig /mnt/usb/psbt/out/final.psbt
```

***

## Kein Key-Austausch zwischen Hot und Cold Wallet

Spätere Verifizierung nicht benötigt, da beim initialen Hot -> Cold eine psbt übertragen wird, die bereits von keyA signiert wurde.
Dies kann verifiziert werden und ein weiterer Hash würde redundanz bedeuten.

Auch ist ein weiterer hash von Cold -> Hot vernahclässigbar, da die Hot Wallet nur noch den USB inhalt broadcasted.
Fehlerhafte, unsignierte, manipuliert TXs würde beim broadcast fehlschlagen oder könnten das cold Wallet nicht addressieren

Zudem soll der USB Flashdrive immernur für eine TX zur selben Zeit verwendet werden