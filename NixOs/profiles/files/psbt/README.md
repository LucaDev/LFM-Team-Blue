# Runbook: **PSBT‑Workflow** (Air‑gapped) + Proxmox „USB‑Stecken“

> Ziel: Hot erstellt eine PSBT → Signer prüft & **approved** (Signer‑GPG Private Key) → KeyB/KeyC **verifizieren Approval** & signieren in Sparrow → Signer kombiniert/finalisiert → Hot broadcastet.  
> **Proxmox Host** ist nur „USB‑Port“ (attach/detach), **keine** inhaltliche Verifikation.  
> **Hot verifiziert nichts** – Broadcast ist operativ, nicht sicherheitskritisch. 

***

## 0) Rollen, Maschinen & Medien

### Proxmox Host

*   Führt **`/root/psbt-usb.sh …`** aus (physisches „einstecken/abziehen“)
*   Attacht das **virtuelle USB‑Medium (qcow2)** als `scsi2` an **genau eine** VM (Exklusivität)
*   Startet VM bei Bedarf (`qm start`)

### VMs

*   **hot**: online, Bitcoin Core (+ ggf. Sparrow watch-only)
*   **signer**: offline, **keine Bitcoin‑Private Keys**, aber **GPG‑Private Key** für Approval
*   **keyB / keyC**: offline, halten Bitcoin‑Keys (Sparrow), haben **Signer‑Public Key** importiert für Authentifizierung

### Medium / Mount

**einzelnes Medium** zum Vorbeugen von Verwechslungen. Dieses beinhält immer nur eine TX und kann somit mit dieser gleichgesetzt werden

*   **Label:** `USB`
*   **Mountpoint:** `/mnt/usb`

***

## 1 Ordnerstruktur auf dem USB-Medium

Auf dem USB (gemountet als `/mnt/usb`) liegen diese möglichen Dateien an einem Schritt:

```text
/mnt/usb/psbt/
  unsigned.psbt         # Hot -> Signer (Input)
  for-signing.<id>.psbt
  for-signing.psbt -> for-signing.<id>.psbt   (alias "latest")
  signed-<host>.<id>.psbt                     (KeyB/KeyC -> Signer) 
  final.<id>.psbt
  final.psbt -> final.<id>.psbt               (alias "latest")
  approval/               # Signer Approval (GPG)
    approval.json
    approval.json.sig
  archive                                           # Verschieben der nicht mehr benötigten Dateien nach jedem Teilschritt
```

### ID‑Definition (eindeutig & debug‑freundlich)

**`<id>`** wird beim Approval vom Signer erzeugt:

*   **empfohlen:** `YYYYmmdd-HHMMSS-<sha256prefix>`
*   `<sha256prefix>` = **kurzer** SHA256‑Prefix (z. B. 12 Zeichen) der `unsigned.psbt` (oder der for-signing Datei)

> PSBT selbst garantiert keinen stabilen „Unique Identifier“, auf den man sich als Dateiname verlassen sollte.  
> Daher: **ID über Zeit + Hash‑Prefix**.

***

## 2 PSBT‑Workflow Schritt für Schritt (mit Dateien, Ort, Zeitpunkt)

> **Jeder `/root/psbt-usb.sh …` Schritt läuft auf dem Proxmox Host.**  
> Alle `mount`/`Sparrow`/`psbt-*.sh` Befehle laufen **in der jeweiligen VM**.

***

### Schritt 2.1 — Hot erstellt PSBT und legt sie auf USB ab

#### 2.1.1 Proxmox Host („USB in Hot stecken“)

```bash
/root/psbt-usb.sh hot
```

#### 2.1.2 Hot‑VM (Datei erzeugen & ablegen)

Mount:

```bash
sudo mount /dev/disk/by-label/USB /mnt/usb
```

Hot erstellt PSBT in sparrow extortiert diese auf den USB

*   **Input‑Datei auf USB:**  
    **`/mnt/usb/psbt/unsigned.psbt`**

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

*   `/mnt/usb/psbt/unsigned.psbt`

***

### Schritt 2.2 — Signer approved die Hot‑PSBT (Signer‑GPG Private Key)

#### 2.2.1 Proxmox Host („USB in Signer stecken“)

```bash
/root/psbt-usb.sh signer
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

*   `/mnt/usb/psbt/unsigned.psbt`

**`psbt-approve.sh` erzeugt (Output):**

*   Approval‑Metadaten (GPG signiert):
    *   `/mnt/usb/psbt/approval/approval.json`
    *   `/mnt/usb/psbt/approval/approval.json.sig`
*   Freigegebene PSBT:
    *   `/mnt/usb/psbt/for-signing.<id>.psbt`  *(unique)*
    *   `/mnt/usb/psbt/for-signing.psbt`       *(alias/symlink von unique)*

**Aufräumen:**

*   `unsigned.psbt` wird nach Approval verschoben
    *   `Von psbt nach psbt/archive

Checks:

```bash
ls -lah /mnt/usb/psbt/approval/
ls -lah /mnt/usb/psbt/
```

Unmount wird automatisch von psbt-approve.sh ausgeführt

**USB-Ordnerstruktur**
```text
/mnt/usb/psbt/
  approval/
    approval.json
    approval.json.sig
  archive      
    unsigned.psbt
  for-signing.<id>.psbt
  for-signing.psbt -> for-signing.<id>.psbt
```

***

### 2.3 — KeyB **oder** KeyC verifiziert Approval und signiert in Sparrow

> Dieser Schritt wird **nur** auf Key‑VMs gemacht.  
> Hier wird `hash-verify.sh` im Sinne von **Approval Verify** ausgeführt.

#### 2.3.1 Proxmox Host („USB in KeyB stecken“)

```bash
/root/psbt-usb.sh keyb
```

#### 2.3.2 Key‑VM verify

Mount:
```bash
sudo mount /dev/disk/by-label/USB /mnt/usb
```

Approval vom Signer werden verifiziert, dies ist noch nicht die Signatur für TX selbst:

```bash
sudo hash-verify.sh
```

**`hash-verify.sh` benötigt:**

*   `/mnt/usb/psbt/for-signing.psbt`
*   `/mnt/usb/psbt/for-signing.psbt.sig` *(oder approval.json(.sig) je nach Implementierung)*

**Output (Konsole):**

*   `OK: Approved vom Signer…`

#### 2.3.3 Key‑VM sign

Dann Signier‑Guidance:

```bash
sudo psbt-sign.sh
```

Sparrow (manuell):

*   Import: `/mnt/usb/psbt/for-signing.psbt`
*   Signieren mit KeyB/KeyC
*   Export:
    *   `/mnt/usb/psbt/signed.<id>.psbt`

***

### Schritt 2.4 — Signer kombiniert Signaturen, finalisiert und erstellt Final‑PSBT

#### 2.4.1 Proxmox Host („USB zurück in Signer stecken“)

```bash
/root/psbt-usb.sh signer
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
    *   `/mnt/usb/psbt/final.psbt` *(alias‑Name)*
    *   oder `/mnt/usb/psbt/final.<id>.psbt` *(unique)*

Unmount.

```bash
sync
sudo umount /mnt/usb
```

**USB-Ordnerstruktur**
```text
/mnt/usb/psbt/
  approval/
    approval.json
    approval.json.sig
  archive      
    unsigned.psbt
    for-signing.<id>.psbt
    for-signing.psbt -> for-signing.<id>.psbt
    signed.<id>.psbt
  final.psbt (alias‑Name)
  final.<id>.psbt (unique)
```

***

### 2.5.1 — Hot importiert Final‑PSBT und broadcastet (ohne Verify)

**Hot führt keinen hash-verify/psbt-verify mehr aus.**

#### 2.5.1 Proxmox Host („USB zurück in Hot stecken“)

```bash
/root/psbt-usb.sh hot
```

#### 2.5.2 Hot‑VM (broadcast)

Mount:

```bash
sudo mount /dev/disk/by-label/PSBTUSB /mnt/usb
```

Hot importiert und broadcastet:

*   Input: `/mnt/usb/psbt/final.psbt`
*   Broadcast via Sparrow/Bitcoin Core

Unmount:

```bash
sync
sudo umount /mnt/usb
```

#### 2.5.3 Archivieren auf Hot-VM
    Archivieren auif der Hot-VM um Buch zu halten