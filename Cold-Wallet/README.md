***

# Runbook – Air‑gapped Hash‑Approval & PSBT‑Workflow

***

## Phase 0 – Voraussetzung (einmalig)

### Hash / GPG‑Public‑Key‑Austausch

***

### 0.1 Signer → Public Key erzeugen & auf USB ablegen

**Proxmox Host**

```bash
psbt_usbFlow signer
```

**Signer‑VM**

```bash
sudo mount /dev/disk/by-label/USB /mnt/usb
sudo hash-keyGen.sh
# Script macht: sync + umount
```

**Proxmox Host**

    ENTER

***

### 0.2 KeyB → Public Key importieren

**Proxmox Host**

```bash
psbt_usbFlow keyb
```

**KeyB‑VM**

```bash
sudo mount /dev/disk/by-label/USB /mnt/usb
sudo hash-keyStore.sh
# Script macht: sync + umount
```

**Proxmox Host**

    ENTER

***

### 0.3 KeyC → Public Key importieren

**Proxmox Host**

```bash
psbt_usbFlow keyc
```

**KeyC‑VM**

```bash
sudo mount /dev/disk/by-label/USB /mnt/usb
sudo hash-keyStore.sh
# Script macht: sync + umount
```

**Proxmox Host**

    ENTER

***

## Phase 1 – PSBT‑Workflow (pro Transaktion)

***

### 1. PSBT erzeugen (Hot)

**Proxmox Host**

```bash
psbt_usbFlow hot
```

**Hot‑VM**

```bash
sudo mount /dev/disk/by-label/USB /mnt/usb
# Sparrow: TX erstellen
# Sparrow: Export → /mnt/usb/psbt/unappr.<id>.psbt
sync
sudo umount /mnt/usb
```

**Proxmox Host**

    ENTER

***

### 2. Approval erstellen (Signer)

**Proxmox Host**

```bash
psbt_usbFlow signer
```

**Signer‑VM**

```bash
sudo mount /dev/disk/by-label/USB /mnt/usb
sudo psbt-approve.sh
# Script erzeugt:
#   psbt/appr.<id>.psbt
#   psbt/auth/approval.json
#   psbt/auth/approval.json.sig
# Script macht: sync + umount
```

**Proxmox Host**

    ENTER

***

### 3. Approval verifizieren & Bitcoin‑Signatur (KeyB oder KeyC)

**Proxmox Host**

```bash
psbt_usbFlow keyb
```

**KeyB‑VM**

```bash
sudo mount /dev/disk/by-label/USB /mnt/usb
sudo hash-verify.sh
# USB bleibt gemountet
# Sparrow:
#   Import → psbt/appr.<id>.psbt
#   Signieren
#   Export → psbt/signed.<id>.psbt
sync
sudo umount /mnt/usb
```

**Proxmox Host**

    ENTER

*(optional: gleiches mit `keyc` wiederholen)*

***

### 4. Combine & Finalize (Signer)

**Proxmox Host**

```bash
psbt_usbFlow signer
```

**Signer‑VM**

```bash
sudo mount /dev/disk/by-label/USB /mnt/usb
# Sparrow:
#   Import → psbt/signed.<id>.psbt
#   Combine / Finalize
#   Export → psbt/final.<id>.psbt
sync
sudo umount /mnt/usb
```

**Proxmox Host**

    ENTER

***

### 5. Broadcast (Hot)

**Proxmox Host**

```bash
psbt_usbFlow hot
```

**Hot‑VM**

```bash
sudo mount /dev/disk/by-label/USB /mnt/usb
# Sparrow / Bitcoin Core:
#   Import → psbt/final.<id>.psbt
#   Broadcast
sync
sudo umount /mnt/usb
```

**Proxmox Host**

    ENTER

***

## Regeln (implizit, ohne Diskussion)

*   **Nur ein USB‑Medium**
*   **Nur eine TX pro USB**
*   **ENTER am Proxmox Host = VM‑Schritt abgeschlossen**
*   **Proxmox prüft nichts**
*   **Hot verifiziert nichts**
*   **Key‑VMs signieren nur nach `hash-verify.sh`**

***

Sparrow setup
Starte sparrow
schalte es in den offline mode 
clicke auf import new file und use mnemneic phrase
Wähle 24 wörter
    in dejem Wort copntainer kannst du einen buchstaben eingeben und kriegst dann eine auswahl an möglcihen passphrases vorgeschlagen
    Fülle so alle wörter und schriebe diese auf
    generiere das wallet
    wähkle script antive...
    wähle ein passwort