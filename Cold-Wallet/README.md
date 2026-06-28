# Runbook – Air-gapped PSBT-Workflow

---

## Ziel

Dieses Runbook beschreibt den operativen Standardprozess für den air-gapped Cold-Wallet-Betrieb.

Der frühere Hash-Approval-Prozess, der Public-Key-Austausch sowie das separate PSBT-Flow-Programm sind nicht mehr Bestandteil des Standardbetriebs. Sie können bei Bedarf als optionale Erweiterungen wieder aufgesetzt werden, sind für die finale Standardarchitektur jedoch nicht erforderlich.

Der Standardmodus ist:

- Cold-Systeme bleiben air-gapped.
- PSBTs werden über ein dediziertes Wechselmedium übertragen.
- Pro Wechselmedium befindet sich immer nur eine Transaktion im Prozess.
- Die manuelle Prüfung in Sparrow Wallet ist verpflichtend.
- Der Broadcast erfolgt ausschließlich im Hot-Kontext.

---

## Rollen und Systeme

### Hot-Wallet / Hot-System

Das Hot-System erstellt die PSBT und broadcastet die finalisierte Transaktion.

Aufgaben:

- Erstellung der Transaktion
- Export der PSBT auf das Wechselmedium
- Import der finalisierten Transaktion
- Broadcast über Bitcoin Core oder die definierte Hot-Wallet-Infrastruktur

Das Hot-System hält Key A beziehungsweise kann die Transaktion initial vorbereiten oder teilweise signieren, abhängig von der konkreten Wallet-Konfiguration.

---

### Key-B-VM

Die Key-B-VM ist ein air-gapped Cold-Signer.

Aufgaben:

- Import der PSBT
- Manuelle Prüfung der Transaktionsdetails
- Signatur mit Key B

---

### Key-C-VM

Die Key-C-VM ist ein weiterer air-gapped Cold-Signer.

Aufgaben:

- Import der PSBT
- Manuelle Prüfung der Transaktionsdetails
- Signatur mit Key C


---

### Cold-Wallet
Das Cold-Wallet wird als Multi-Sig Wallet betrieben und enthält dementsprechend als Watch-Only Wallet kein privates Schlüsselmaterial.

Es kann auf derselben VM wie Key B oder Key C betrieben werden, da:
- keine privaten Schlüssel enthalten sind
- lediglich Koordinations- und Anzeige-Funktion erfolgt

Aufgabe:

- Zusammenführen von Signaturen
- Finalisierung der Transaktion

### Wechselmedium

Das Wechselmedium dient ausschließlich dem kontrollierten Datentransfer zwischen Hot- und Cold-Systemen.

Regeln:

- Nur ein dediziertes Medium verwenden.
- Vor jedem neuen Vorgang alte Transaktionsdaten entfernen.
- Pro Zeitpunkt nur eine Transaktion auf dem Medium speichern.
- Das Medium nach jedem Schritt sauber aushängen.
- Kein automatischer Bulk-Transfer mehrerer Transaktionen.

---

## Phase 0 – Einmaliges Setup

über das folgende script kann die neuste Version von dem NixOS cold-Wallet heruntergeladen und vollautomatisch instelliert werden.
```bash
setup/setup.sh
```


### 0.1 Key A – Descriptor / Xpub Export

Da Key A im Hot-System liegt, müssen die für die Multisignatur benötigten Informationen kontrolliert exportiert werden.
Dieser key wurde vollautomatisch im NisOS für das Hot-Wallet deklarativ per one-shot erstellt.
Der intiale 24 Wörter mnemonic Seed phrase kann über den Status des service Programs eingesehen und physisch notiert werden:
```bash
systemctl status signer-intit
```

Zudem sollte das Log daraufhin gelöscht werden:
```bash
sudo journalctl --vacuum-time=5s
```

Manuelle Schritte auf dem Hot-System:

1. USB einstecken
2. Script psbt/wgHMAC_export.sh ausführen
3. USB entfernen

Ergebnis:
/mnt/usb/wallets/hot/meta.json
/mnt/usb/wallets/hot/hot-wallet.descriptor
/mnt/usb/wallets/hot/xpub.txt


Hinweis:
Es wird ausschließlich der öffentliche Anteil exportiert. Private Schlüsselmaterialien verbleiben im Hot-System verschlüsselt im TPM.
Ein ausführlichere Beschreibung kann in der README.md von Key A nachgelesen werden


### 0.2 Cold-VMs vorbereiten

Auf den VMs Key B und Key C:

1. Netzwerkadapter auf Hypervisor-Ebene entfernen
3. Sparrow Wallet starten.
5. Wallet anlegen oder importieren.
6. Mnemonic sicher physisch notieren.
7. Optional:  Sparrow-Wallet-Passwort setzen.
8. Wallet-Informationen beziehungsweise Xpubs/Descriptoren kontrolliert exportieren.
   
-----------------------beachgten, dass der master key manuell intregriegt werden muss???

Hinweis:

In der Laborumgebung kann Sparrow im Regtest-Modus starten. Für produktive Nutzung muss die entsprechende Startoption, `--regtest`, aus der Sparrow-Konfiguration entfernt werden.

---

### 0.3 Sparrow-Wallet auf Key B einrichten

Auf Key B wird das Cold-Multisig-Wallet beziehungsweise das Watch-Only-Koordinationswallet eingerichtet.

Vorgehen:

1. Sparrow starten
2. Neues Wallet → Multisig
3. Policy setzen:
   ```
   2 aus 3
   ```
4. Schlüssel hinzufügen:
   * Key A (importieren)
   * Key B (lokal)
   * Key C (importieren)

5. Script-Typ wählen Native SegWit
6. Wallet erstellen

***

## 0.4 Wechselmedium vorbereiten

Der Datentransfer erfolgt ausschließlich über ein dediziertes USB-Medium.

Zum Mounten:

```bash
sudo psbt/setup/mnt_usb.sh
```

Alternativ manuell:

```bash
sudo mount /dev/disk/by-label/USB /mnt/usb
```

Zum Bereinigen des Mediums:

```bash
sudo psbt/setup/format_usb.sh
```

Dieses Skript:

* entfernt vorhandene Dateien vollständig
* sorgt für einen definierten Ausgangszustand
* reduziert Risiko von Verwechslungen oder Altzuständen

Nach jeder Nutzung zwingend:

```bash
psbt/setup/umnt_usb.sh
```


## 0.5 Descriptor exportieren

Der Multisig-Descriptor wird exportiert und auf dem Wechselmedium gespeichert:

```bash
/wallets/cold/cold-signer.descriptor
```

Dieser dient zur Registrierung im Hot-System.

***

***

# 1. Transaktionsprozess (Standard Flow)

***

## 1.1 PSBT extrahieren (Hot-System)

Das Hot-System überwacht den verfügbaren Bestand für operative Transaktionen.
Unterschreitet dieser eine definierte Schwelle nach ausführen einer automatischen Transaktion für die Hot-Wallet, wird automatisch eine Refill-Transaktion erzeugt.

Diese:
- wird mit Key A teilweise signiert
- enthält alle notwendigen Parameter für die Auffüllung des Hot-Wallets
- wird als PSBT bereitgestellt

Der Operator wird über ntfy via GrapheneOS informiert.

Die PSBT kann anschließend auf das Wechselmedium exportiert werden:

```bash
sudo psbt/export_refill.sh
```

Hinweis:
Ein ausführlichere Beschreibung kann in der README.md von Hot-Wallet nachgelesen werden

***

## 1.2 Signierung (Key B)

Wechselmedium auf Key B einbinden:

```bash
sudo psbt/setup/mnt_usb.sh
```

In Sparrow:
1. PSBT importieren
2. Vollständige manuelle Verifikation:
   * Zieladresse korrekt
   * Betrag korrekt
   * Gebühren plausibel
   * UTXOs korrekt
3. Nur bei vollständiger Plausibilität:
   → Signieren
4. Export:

```bash
/mnt/usb/psbt/signed-keyb.psbt
```

Danach:

```bash
sudo psbt/setup/umnt_usb.sh
```

***

## 1.3 Optionale dritte Signatur (Key C)

Falls benötigt:

```bash
sudo psbt/setup/mnt_usb.sh
```

In Sparrow:

1. Signierte PSBT importieren
2. Erneute vollständige Prüfung
3. Signieren

Export:
```bash
/mnt/usb/psbt/signed-keyb-keyc.psbt
```

Danach:
```bash
sudo psbt/setup/umnt_usb.sh
```

***

## 1.4 Finalisierung & Broadcast (Hot-System)

Auf dem Hot-System:

```bash
sudo psbt/broadcast_psbt
```

Dann:

1. Finalisiert PSBT
3. Führt Broadcast durch


***

# 3. Operative Regeln

* Cold-Systeme sind dauerhaft air‑gapped
* keine Netzwerkverbindungen auf Key B / Key C
* ausschließlich ein dediziertes USB-Medium verwenden
* pro Zeitpunkt genau eine Transaktion auf dem Medium
* jede Signatur erfordert manuelle Verifikation, wobei der Operator die Verantwortung für die vollständige Verifikation der Transaktion trägt
* keine automatische Freigabe
* nach jedem Schritt:
 ```bash
sudo psbt/setup/umnt_usb.sh
```
* Broadcast erfolgt ausschließlich im Hot-System

***

# 4. Hilfsprogramme

Die bereitgestellten Skripte unterstützen den operativen Ablauf, ersetzen jedoch keine Sicherheitsentscheidungen.
Können vom Operator genutzt werden, um eine schnellere und leichtere Bedienung zu haben.

Alle Scripte sind ebenfalls auf dem Desktop unter /psbt verfügbar und können per Doppelklick ausgeführt werden.

***

## psbt/setup/mnt\_usb.sh

Zweck:

* standardisiertes Mounten des Wechselmediums
* konsistenter Mount-Pfad (`/mnt/usb`)

***

## psbt/setup/umnt\_usb.sh

Zweck:

* standardisiertes Unmounten des Wechselmediums
* Synchrioniseren + schnelleres Entdernen

***

## psbt/setup/format\_usb.sh

Zweck:

* vollständige Bereinigung des Mediums
* Entfernen alter PSBTs und Artefakte

Einsatz:

* vor Beginn eines neuen Prozesses
* bei Unsicherheiten über den Zustand des Mediums

***

## psbt/setup/airgap.sh

Zweck:

* Sichert das System mit Entfernen aller Internet Interfaces ab
* Rebuild und switch des NixOS mit den neuen Regeln bzw. Deklarationen

Einsatz:

* Artefakt als Sparrow Wallet als Cold-Wallet Koordinator noch kurzzeitig mit dem Internet verbunden sein sollte zum Registrieren der Wallet
* Nun dem Mandanten zum Ein- und Ausschalten des airgaps überlassen

***

## psbt/setup/online.sh

Zweck:

* Richtet Internet Interfaces für den Zugriff zum Internet ein
* Rebuild und switch des NixOS mit den neuen Regeln bzw. Deklarationen

Einsatz:

* Artefakt als Sparrow Wallet als Cold-Wallet Koordinator noch kurzzeitig mit dem Internet verbunden sein sollte zum Registrieren der Wallet
* Nun dem Mandanten zum Ein- und Ausschalten des airgaps überlassen


***

## psbt/setup/setup.sh

Zweck:

* Konfiguriert das gesamte System für die Installation von NixOS vollautomatisch
* Inklusive bauen der Partitionen des OS und Herunterladen von Pkgs

Einsatz:

* Kann vom mandanten genutzt werden, um die NixOS Dateien vollautomatisch von github herunterzuladen und zu installieren
* Empfohlen für den Initial Setup
