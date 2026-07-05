# Runbook – Air-gapped PSBT-Workflow (Cold-Wallet)

***

## Ziel

Dieses Runbook beschreibt den operativen Standardprozess für den air-gapped Cold-Wallet-Betrieb.

Der frühere Hash-Approval-Prozess, der Public-Key-Austausch sowie das separate PSBT-Flow-Programm sind nicht mehr Bestandteil des Standardbetriebs. Sie können bei Bedarf als optionale Erweiterungen wieder aufgesetzt werden, sind für die finale Standardarchitektur jedoch nicht erforderlich.

Der Standardmodus ist:

* Cold-Systeme bleiben air-gapped.
* PSBTs werden über ein dediziertes Wechselmedium übertragen.
* Pro Wechselmedium befindet sich immer nur eine Transaktion im Prozess.
* Die manuelle Prüfung in Sparrow Wallet ist verpflichtend.
* Der Broadcast erfolgt ausschließlich im Hot-Kontext.

***

## Systemhärtung – operative Auswirkungen

Die Cold-Signer-VMs sind über NixOS deklarativ gehärtet (nftables, Kernel-Härtung, kein Auto-Mount, `systemd-boot`-Editor deaktiviert). Die technischen Details stehen in der Projektdokumentation (Abschnitt *Cold-Wallet → Sicherheitsmodell*). Für den Betrieb sind drei Punkte relevant:

* **Festplattenverschlüsselung (LUKS):** Bei jedem Start der VM wird eine Disk-Passphrase abgefragt. Ohne diese bootet das System nicht.
* **Air-Gap ist Standard:** Nach dem Build bootet die VM automatisch vollständig air-gapped. Ein Online-Modus existiert nur als separater Boot-Eintrag bzw. Skript (siehe Abschnitt *Air-Gap / Online umschalten*).
* **Login:** Anmeldung als Benutzer `user`mit dem beim Setup gesetzten Passwort (es gibt kein Standardpasswort).

***

## Rollen und Systeme

### Hot-Wallet / Hot-System

Das Hot-System erstellt die PSBT und broadcastet die finalisierte Transaktion.

Aufgaben:

* Erstellung der Transaktion
* Export der PSBT auf das Wechselmedium
* Import der finalisierten Transaktion
* Broadcast über Bitcoin Core oder die definierte Hot-Wallet-Infrastruktur

Das Hot-System hält Key A beziehungsweise kann die Transaktion initial vorbereiten oder teilweise signieren, abhängig von der konkreten Wallet-Konfiguration.

***

### Key-B-VM

Die Key-B-VM ist ein air-gapped Cold-Signer.

Aufgaben:

* Import der PSBT
* Manuelle Prüfung der Transaktionsdetails
* Signatur mit Key B

***

### Key-C-VM

Die Key-C-VM ist ein weiterer air-gapped Cold-Signer.

Aufgaben:

* Import der PSBT
* Manuelle Prüfung der Transaktionsdetails
* Signatur mit Key C

***

### Cold-Wallet

Das Cold-Wallet wird als Multi-Sig-Wallet betrieben und enthält dementsprechend als Watch-Only-Wallet kein privates Schlüsselmaterial.

Es kann auf derselben VM wie Key B oder Key C betrieben werden, da:

* keine privaten Schlüssel enthalten sind
* lediglich Koordinations- und Anzeige-Funktion erfolgt

Aufgabe:

* Zusammenführen von Signaturen
* Finalisierung der Transaktion

***

### Wechselmedium

Das Wechselmedium dient ausschließlich dem kontrollierten Datentransfer zwischen Hot- und Cold-Systemen.

Regeln:

* Nur ein dediziertes Medium verwenden.
* Vor jedem neuen Vorgang alte Transaktionsdaten entfernen.
* Pro Zeitpunkt nur eine Transaktion auf dem Medium speichern.
* Das Medium nach jedem Schritt sauber aushängen.
* Kein automatischer Bulk-Transfer mehrerer Transaktionen.

***

## Phase 0 – Einmaliges Setup

### 0.0 Installation

Über das folgende Skript kann die neueste Version des NixOS-Cold-Wallets heruntergeladen und automatisiert installiert werden. Es wird von der NixOS-Installer-ISO aus ausgeführt:

```bash
sudo /home/user/Desktop/scripts/setup/setup.sh
```

Während der Installation:

* wird die Root-Partition mit LUKS verschlüsselt – dabei nach einer **Disk-Passphrase** gefragt (sicher notieren);
* werden die Flake-Inputs gepinnt (`flake.lock`), sofern nicht bereits im Repository vorhanden.

Nach dem ersten Boot fragt das System bei jedem Start die Disk-Passphrase ab und startet air-gapped.

***

### 0.1 Key A – Descriptor / Xpub Export (Hot-System)

Da Key A im Hot-System liegt, müssen die für die Multisignatur benötigten Informationen kontrolliert exportiert werden. Dieser Key wurde im NixOS des Hot-Systems deklarativ per One-Shot erstellt. Die initiale 24-Wort-Mnemonic kann über den Status des Init-Service eingesehen und physisch notiert werden:

```bash
systemctl status signer-init
```

Anschließend sollte das Log bereinigt werden:

```bash
sudo journalctl --vacuum-time=5s
```

Manuelle Schritte **auf dem Hot-System**:

1. USB einstecken
2. Skript `wgHMAC_export.sh`ausführen (Details siehe README des Hot-KeyHolders)
3. USB entfernen

Ergebnis auf dem Medium:

```
/mnt/usb/wallet/hot/metadata.json
/mnt/usb/wallet/hot/descriptor.public.txt
/mnt/usb/wallet/hot/xpub.txt
/mnt/usb/wallet/cold/keyA.meta.json
​```

Hinweis:
Es wird ausschließlich der öffentliche Anteil exportiert. 
Privates Schlüsselmaterial verbleibt im Hot-System, TPM-versiegelt. 
Eine ausführlichere Beschreibung steht in der README des Hot-KeyHolders (Key A).

`wallet/cold/keyA.meta.json`ist der **48h-Cosigner-Anteil** von Key A für das Cold-Multisig (`[fingerprint/48h/1h/0h/2h]xpub`). 
Dieser, nicht der 84h-Hot-Descriptor, wird beim Multisig-Aufbau als Key A eingesetzt.

***

### 0.2 Cold-VMs vorbereiten

Auf den VMs Key B und Key C:

1. Netzwerkadapter auf Hypervisor-Ebene entfernen (die VM ist zusätzlich per NixOS air-gapped).
2. Sparrow Wallet starten.
3. Wallet anlegen oder importieren.
4. Mnemonic sicher physisch notieren.
5. Optional (empfohlen): Sparrow-Wallet-Passwort setzen.
6. Wallet-Informationen bzw. Xpubs/Deskriptoren kontrolliert exportieren.

Hinweis: In der Laborumgebung startet Sparrow im Regtest-Modus. Für den produktiven Betrieb den Netzmodus über die deklarative Option setzen (`cold.sparrowNetwork = "mainnet";`in `configuration.nix`) und die VM neu bauen.

***

### 0.3 Cold-Multisig in Sparrow einrichten (Key B)

Das Cold-Wallet wird **direkt** als Multisig angelegt und nicht aus drei Single-Sig-Wallets zusammenkopiert. 
Nur so leitet Sparrow jeden Cosigner korrekt unter BIP48/P2WSH (`m/48'/1'/0'/2'`) ab.

1. Sparrow → File → New Wallet → Name vergeben
2. **Policy Type: Multi Signature**, Schwelle `2 of 3`
3. **Script Type: Native SegWit (P2WSH)** → ergibt automatisch `m/48'/1'/0'/2'`
4. Keystores:
   * **Key B** (lokal): „New or Imported Software Wallet" → Seed. Sparrow zeigt
     Derivation `m/48'/1'/0'/2'`– nicht ändern.
   * **Key A** (extern): xpub aus `wallet/cold/keyA.meta.json`importieren.
     **Nicht** den 84h-Hot-Descriptor verwenden.
   * **Key C** (extern): dessen 48h-xpub importieren. (Von Schritt 4 auf einer anderen VM für Key C)
5. Wallet erstellen.

Als Ergebnis haben wir 2 VMs auf denen je eine Multi-Sig Wallet liegt.
Jede dieser Wallet besitzt nur einen geheimen Schlüssel, die anderen beiden sind als öffentliche xpubs integriert.

Zu beachten ist, dass für jede VM erst die Seed phrase als geheimes Schlüsselmaterial festgelegt werden und dann ausgetauscht werden muss.
Ein Bilden der 48er Ableitung durch eine Single-Wallet ist nicht möglich.

Dementsprechend wird der öffentliche Schlüssel des geheimen Materials nach Eingabe und vor Finalisierung bereits mit dem richtigen Ableitungspfad angezeigt und muss mit dem je anderen Wallet per USB manuell ausgetauscht werden.
Erst nach Eingabe aller Schlüssel kann finalisiert (apply) werden.

Der genaue Fingerprint muss ebenfalls übertragen werden.
Bei korrektem Erstellen haben die Multi-Sig Wallet auf der VM von Key B und Key C denselben wsh-deskriptor.
Dies ist einfach an der Checksumme am Ende zu erkennen.

**Merksatz:** Origin-Label und xpub müssen zusammenpassen. 
Ein 84h-xpub unter einem 48h-Label führt dazu, dass Key A die Cold-PSBT nicht signieren kann (`sign_with`findet keinen passenden Schlüssel).



***

### 0.4 Wechselmedium vorbereiten

Der Datentransfer erfolgt ausschließlich über ein dediziertes USB-Medium.

Mounten (Doppelklick auf dem Desktop oder im Terminal):

```bash
/home/user/Desktop/scripts/setup/mnt-USB.sh
```

Alternativ manuell:

```bash
sudo mount /dev/disk/by-label/USB /mnt/usb
```

Bereinigen/Formatieren des Mediums. Aus Sicherheitsgründen ist hierfür das Zielgerät **explizit** anzugeben (kein Doppelklick), damit nicht versehentlich die falsche Platte gelöscht wird:

```bash
sudo /home/user/Desktop/scripts/setup/format-USB.sh /dev/disk/by-id/<DEIN-STICK>
```

Dieses Skript:

* fordert eine Bestätigung an, bevor es formatiert
* entfernt vorhandene Dateien vollständig
* vergibt das Volume-Label `USB`für die nachfolgenden Prozesse

Nach jeder Nutzung zwingend aushängen:

```bash
/home/user/Desktop/scripts/setup/umnt-USB.sh
```

***

### 0.5 Descriptor exportieren

Der zusammengesetzte `wsh(sortedmulti(...))`-Descriptor wird als Datei auf dem
Wechselmedium abgelegt:

​```
/mnt/usb/wallet/cold/cold-signer.wsh
​```

Der automatische Import auf dem Basis-System (`wallet_import.sh`) liest die
letzte Zeile dieser Datei als Descriptor. Dateiname `cold-signer.wsh`(nicht
`.descriptor`), damit der Import ihn findet.

***

## Air-Gap / Online umschalten

Der air-gapped Zustand ist der Standard und wird direkt beim Build aktiviert. Für die einmalige Wallet-Registrierung kann kurzzeitig ein Online-Modus aktiviert werden. Dieser ist als NixOS-*specialisation* umgesetzt – es wird also **nichts** an der Konfiguration editiert und kein Neubau nötig.

**Online aktivieren** (Netz an, nur zum Registrieren) – Doppelklick oder Terminal:

```bash
/home/user/Desktop/scripts/setup/online.sh
```

Alternativ beim Reboot im systemd-boot-Menü den Eintrag **„NixOS (online)"** wählen.

**Wieder air-gappen:**

```bash
/home/user/Desktop/scripts/setup/airgap.sh
```

Ein normaler Reboot landet immer im air-gapped Standard. Nach Abschluss der Registrierung sollte die VM dauerhaft air-gapped betrieben werden.

***

# 1. Transaktionsprozess (Standard-Flow)

***

## 1.1 PSBT extrahieren (Hot-System)

Das Hot-System überwacht den verfügbaren Bestand für operative Transaktionen. Unterschreitet dieser eine definierte Schwelle, wird automatisch eine Refill-Transaktion erzeugt.

Diese:

* wird mit Key A teilweise signiert
* enthält alle notwendigen Parameter für die Auffüllung des Hot-Wallets
* wird als PSBT bereitgestellt

Der Operator wird über ntfy (GrapheneOS) informiert und exportiert die PSBT **auf dem Hot-System** auf das Wechselmedium (Skriptdetails siehe README des Hot-Wallets).

***

## 1.2 Signierung (Key B)

Wechselmedium auf Key B einbinden:

```bash
/home/user/Desktop/scripts/setup/mnt-USB.sh
```

In Sparrow:

1. PSBT importieren
2. Vollständige manuelle Verifikation:
   * Zieladresse korrekt
   * Betrag korrekt
   * Gebühren plausibel
   * UTXOs korrekt
3. Nur bei vollständiger Plausibilität signieren
4. Signierte PSBT exportieren, z. B. `/mnt/usb/psbt/signed-keyb.psbt`

Danach aushängen:

```bash
/home/user/Desktop/scripts/setup/umnt-USB.sh
```

***

## 1.3 Optionale dritte Signatur (Key C)

Falls benötigt, Medium auf Key C einbinden:

```bash
/home/user/Desktop/scripts/setup/mnt-USB.sh
```

In Sparrow:

1. Signierte PSBT importieren
2. Erneute vollständige Prüfung
3. Signieren
4. Exportieren, z. B. `/mnt/usb/psbt/signed-keyb-keyc.psbt`

Danach aushängen:

```bash
/home/user/Desktop/scripts/setup/umnt-USB.sh
```

***

## 1.4 Finalisierung & Broadcast (Hot-System)

Auf dem Hot-System wird die PSBT importiert, finalisiert und über Bitcoin Core gebroadcastet (Skriptdetails siehe README des Hot-Wallets).

***

# 2. Operative Regeln

* Cold-Systeme sind dauerhaft air-gapped
* keine Netzwerkverbindungen auf Key B / Key C (außer bewusst gewähltem Online-Modus zur Registrierung)
* ausschließlich ein dediziertes USB-Medium verwenden
* pro Zeitpunkt genau eine Transaktion auf dem Medium
* jede Signatur erfordert manuelle Verifikation; der Operator trägt die Verantwortung für die vollständige Prüfung der Transaktion
* keine automatische Freigabe
* nach jedem Schritt aushängen: `/home/user/Desktop/scripts/setup/umnt-USB.sh`
* Broadcast erfolgt ausschließlich im Hot-System

***

# 3. Hilfsprogramme

Die bereitgestellten Skripte unterstützen den operativen Ablauf, ersetzen jedoch keine Sicherheitsentscheidungen. Sie liegen auf dem Desktop unter `scripts/setup/`und sind – mit Ausnahme von `format-USB.sh`– per Doppelklick ausführbar.

***

## mnt-USB.sh

Zweck:

* standardisiertes Mounten des Wechselmediums
* konsistenter Mount-Pfad (`/mnt/usb`)

***

## umnt-USB.sh

Zweck:

* standardisiertes Aushängen des Wechselmediums
* Synchronisieren + sicheres Entfernen

***

## format-USB.sh &lt;gerät&gt;

Zweck:

* vollständige Bereinigung des Mediums
* Entfernen alter PSBTs und Artefakte
* vergibt das Volume-Label `USB`

Einsatz:

* Zielgerät explizit angeben (z. B. `/dev/disk/by-id/...`), mit Sicherheitsabfrage
* vor Beginn eines neuen Prozesses
* bei Unsicherheiten über den Zustand des Mediums

***

## airgap.sh

Zweck:

* schaltet das System in den air-gapped Standard (specialisation)

***

## online.sh

Zweck:

* aktiviert kurzzeitig den Online-Modus (specialisation), z. B. zum Registrieren der Wallet
* danach über `airgap.sh`oder Reboot wieder air-gappen

***

## setup.sh

Zweck:

* konfiguriert das gesamte System für die Installation von NixOS vollautomatisch
* inklusive LUKS-Verschlüsselung, Partitionierung und Flake-Pinning

Einsatz:

* Initial-Setup von der Installer-ISO

***

# 4. Reproduzierbarkeit / Build

Die Cold-Konfiguration ist ein NixOS-Flake. Zum lokalen Prüfen bzw. Neubau (ohne Installation):

```bash
cd /etc/nixos
nixos-rebuild build --flake .#cold --impure
```

Die Inputs sind über `flake.lock`gepinnt; ein bewusstes Update erfolgt mit `nix flake update`. Änderungen an der Systemkonfiguration werden mit `nixos-rebuild switch --flake .#cold`aktiviert.
