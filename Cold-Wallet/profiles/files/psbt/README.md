# Runbook: **PSBT‑Workflow** (Air‑gapped) + Proxmox „USB‑Stecken“

> Ziel: Hot erstellt eine PSBT → Signer prüft & **approved** (Signer‑GPG Private Key) → KeyB/KeyC **verifizieren Approval** & signieren in Sparrow → Signer kombiniert/finalisiert → Hot broadcastet.  
> **Proxmox Host** ist nur „USB‑Port“ (attach/detach), **keine** inhaltliche Verifikation.  
> **Hot verifiziert nichts** – Broadcast ist operativ, nicht sicherheitskritisch. 

***

## 0) Rollen, Maschinen & Medien

### Proxmox Host

*   Führt **`/root/psbt-usbFlow.sh …`** aus (physisches „einstecken/abziehen“)
*   Attacht das **virtuelle USB‑Medium (qcow2)** als `scsi2` an **genau eine** VM (Exklusivität)
*   Startet VM bei Bedarf (`qm start`)

### VMs

*   **hot**: online, Bitcoin Core (+ ggf. Sparrow watch-only)
*   **signer**: offline, **keine Bitcoin‑Private Keys**, aber **GPG‑Private Key** für Approval
*   **keyB / keyC**: offline, halten Bitcoin‑Keys (Sparrow), haben **Signer‑Public Key** importiert für Authentifizierung

### Medium / Mount

**einzelnes Medium** zum Vorbeugen von Verwechslungen. Dieses beinhaltet immer nur eine TX und kann somit mit dieser gleichgesetzt werden

*   **Label:** `USB`
*   **Mountpoint:** `/mnt/usb`

***

## 1 Ordnerstruktur auf dem USB-Medium

Auf dem USB (gemountet als `/mnt/usb`) liegen diese möglichen Dateien an einem Schritt:

```text
/mnt/usb/psbt/
  unappr.<id>.psbt          # Hot -> Signer (Input)
  appr.<id>.psbt           # Signer -> Key-Holder
  signed.<id>.psbt          # Key-Holder -> Signer
  final.<id>.psbt           # Signer -> Hot
  auth/
    approval.json          # Auth Signer -> Key-Holder
    approval.json.sig      # Auth Signer -> Key-Holder
  archive
```
Archiv ist append‑only und dient ausschließlich Audit / Debug,
niemals als Input für weitere Schritte

### ID‑Definition (eindeutig & debug‑freundlich)

**`<id>`** wird beim Erstellen vom Hot-Wallet erzeugt:

*   **empfohlen:** `YYYYmmdd-HHMMSS-<sha256prefix>`
*   `<sha256prefix>` = **kurzer** SHA256‑Prefix (z. B. 12 Zeichen) der `unappr.<id>.psbt`

> PSBT selbst garantiert keinen stabilen „Unique Identifier“, auf den man sich als Dateiname verlassen sollte.  
> Daher: **ID über Zeit + Hash‑Prefix**.

***

## 2 PSBT‑Workflow Schritt für Schritt (mit Dateien, Ort, Zeitpunkt)

> **Jeder `/root/psbt-usbFlow.sh …` Schritt läuft auf dem Proxmox Host.**  
> Alle `mount`/`Sparrow`/`psbt-*.sh` Befehle laufen **in der jeweiligen VM**.

***

### Schritt 2.1 — Hot erstellt PSBT und legt sie auf USB ab

#### 2.1.1 Proxmox Host („USB in Hot stecken“)

```bash
/root/psbt-usbFlow.sh hot
```

#### 2.1.2 Hot‑VM (Datei erzeugen & ablegen)

Mount:

```bash
sudo mount /dev/disk/by-label/USB /mnt/usb
```

Hot erstellt PSBT in sparrow exportiert diese auf den USB

*   **Input‑Datei auf USB:**  
    **`/mnt/usb/psbt/unappr.<id>.psbt`**

Check:

```bash
ls -lah /mnt/usb/psbt/
```

Unmount:

```bash
sync
sudo umount /mnt/usb
```

> Danach <ENTER> auf dem Proxmox Host, damit detach passiert.

**Erwarteter Output nach Schritt A (auf USB):**

*   `/mnt/usb/psbt/unappr.<id>.psbt`

***

### Schritt 2.2 — Signer approved die Hot‑PSBT (Signer‑GPG Private Key)

#### 2.2.1 Proxmox Host („USB in Signer stecken“)

```bash
/root/psbt-usbFlow.sh signer
```

#### 2.2.2 Signer‑VM: Approval

Mount:

```bash
sudo mount /dev/disk/by-label/USB /mnt/usb
```

Approve:

```bash
sudo psbt-approve.sh
```

**`psbt-approve.sh` benötigt (Input):**

*   `/mnt/usb/psbt/unappr.<id>.psbt`

**`psbt-approve.sh` erzeugt (Output):**

*   Approval‑Metadaten (GPG signiert):
    *   `/mnt/usb/psbt/auth/approval.json`
    *   `/mnt/usb/psbt/auth/approval.json.sig`
*   Freigegebene PSBT:
    *   `/mnt/usb/psbt/appr.<id>.psbt`

**Aufräumen:**

*   `unappr.<id>.psbt` wird nach Archive verschoben
    *   `Von psbt nach psbt/archive

Checks:

```bash
ls -lah /mnt/usb/psbt/auth/
ls -lah /mnt/usb/psbt/
```

Unmount wird automatisch von psbt-approve.sh ausgeführt

**USB-Ordnerstruktur**
```text
/mnt/usb/psbt/
  auth/
    approval.json
    approval.json.sig
  archive      
    unappr.<id>.psbt
  appr.<id>.psbt
```

***

### 2.3 — KeyB **oder** KeyC verifiziert Approval und signiert in Sparrow

> Dieser Schritt wird **nur** auf Key‑VMs gemacht.  
> Hier wird `hash-verify.sh` im Sinne von **Approval Verify** ausgeführt.

#### 2.3.1 Proxmox Host („USB in KeyB stecken“)

```bash
/root/Flow.sh keyb
```

#### 2.3.2 Key‑VM verify

Mount:
```bash
sudo mount /dev/disk/by-label/USB /mnt/usb
```

Approval vom Signer werden verifiziert, dies ist noch nicht die Signatur für TX selbst.
Vorraussetzung, dass Voraussetzung Signer‑PubKey bereits in GNUPGHOME importiert wurde (via hash-keyStore.sh).

```bash
sudo hash-verify.sh
```

**`hash-verify.sh` benötigt:**

*   `/mnt/usb/psbt/auth/approval.json`
*   `/mnt/usb/psbt/auth/approval.json.sig`

**Output (Konsole):**

*   `OK: Approval vom Signer…`

#### 2.3.3 Key‑VM Signieren in Sparrow-desktop

Sparrow (manuell):

*   Import: `/mnt/usb/psbt/appr.<id>.psbt`
*   Signieren mit KeyB/KeyC
*   Export:
    *   `/mnt/usb/psbt/signed.<id>.psbt`

***

### Schritt 2.4 — Signer kombiniert und finalisiert

#### 2.4.1 Proxmox Host („USB zurück in Signer stecken“)

```bash
/root/psbt-usbFlow.sh signer
```

#### 2.4.2 Signer‑VM: combine/finalize

Mount:

```bash
sudo mount /dev/disk/by-label/USB /mnt/usb
```

Sparrow (manuell):

*   Import: `psbt/signed.<id>.psbt`
*   Combine / Finalize
*   Export final:
    *   `/mnt/usb/psbt/final.<id>.psbt`

Unmount.

```bash
sync
sudo umount /mnt/usb
```

**USB-Ordnerstruktur**
```text
/mnt/usb/psbt/
  auth/
    approval.json
    approval.json.sig
  archive 
    unappr.<id>.psbt     
    appr.<id>.psbt
    signed.<id>.psbt
  final.<id>.psbt
```

***

### 2.5.1 — Hot importiert Final‑PSBT und broadcastet (ohne Verifizieren)

**Hot führt keinen hash-verify/psbt-verify mehr aus.**

#### 2.5.1 Proxmox Host („USB zurück in Hot stecken“)

```bash
/root/psbt-usbFlow.sh hot
```

#### 2.5.2 Hot‑VM (broadcast)

Mount:

```bash
sudo mount /dev/disk/by-label/USB /mnt/usb
```

Hot importiert und broadcastet:

*   Input: `/mnt/usb/psbt/final.<id>.psbt`
*   Broadcast via Sparrow/Bitcoin Core

Unmount:

```bash
sync
sudo umount /mnt/usb
```

#### 2.5.3 Archivieren auf Hot-VM
    Archivieren auf der Hot-VM um Buch zu halten