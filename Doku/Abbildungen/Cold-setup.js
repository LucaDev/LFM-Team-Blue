flowchart TD

A["NixOS-Image installieren (Key-B-VM und Key-C-VM)"]
A -->|"1. nixos-rebuild switch (laedt Skripte/Programme deklarativ)"| B["Systeminstallation"]
B -->|"2. LAN-Bridge entfernen (Hypervisor/Hardware)"| C["Air-Gap aktiv"]
C -->|"3. Sparrow oeffnen (regtest)"| D["Sparrow bereit"]
D -->|"4. je VM: Wallet importieren ODER neue Mnemonic (physisch notieren)"| E["Einzel-Signer eingerichtet"]

%% xpub-Einsammlung der drei Cosigner
E -->|"5a. xpub Key C -> /wallets/cold (USB via mnt_usb.sh)"| XC["xpub Key C"]
KA["Key-A-VM (Hot)"] -->|"5b. wgHMAC_export.sh: xpub Key A + meta.json auf USB"| XA["xpub Key A"]

%% Zusammenfuehrung auf der Key-B-VM
XC --> G["Key-B-VM: 2-of-3 Multisig anlegen"]
XA --> G
G -->|"6. xpub Key B lokal kopieren, A+B+C kombinieren"| H["wsh-Deskriptor (2-of-3)"]
H -->|"7. Export: /Wallets/Cold/cold-signer.descriptor (USB)"| I["Import auf Basis-System"]

%% Watch-Only fuer Zieladress-Aufloesung
G -->|"8. Key A als Watch-Only in Sparrow registrieren"| J["dynamische Zieladressen aufloesbar"]