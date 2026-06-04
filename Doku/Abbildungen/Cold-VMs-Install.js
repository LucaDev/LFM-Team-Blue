flowchart TD

A["Create NixOS VM"]

A -->|"1. nixos-rebuild switch"| B["System Installation"]

B -->|"2. Sparrow Multi-Sig Wallet generieren"| C["2-of-3 Wallet auf Koordinator VM"]

C -->|"3. Netzwerk deaktivieren"| D["Air-Gap Enforcement"]

D -->|"5. XPUB auf USB exportieren"| E

F -->|"6. USB auf je key B, key C VM umstecken"| H["Key Holder B/C"]

%% USB
Z["USB"]

Z -->|"4. scripts/auth/usb-mnt.sh"| E["mounted USB"]

%% Approval Key

E -->|"6. scripts/auth/hash-keyGen.sh"| F["Hash Paar generieren + public Key auf USB speicher"]

H -->|"7. scripts/auth/usb-mnt.sh"| I["mounted USB"]

I -->|"8. scripts/auth/hash-keyStore.sh"| K["Public Key Extrahieren"]

K -->|"9. Viusuelle Fingerprint Verifizierung"| L["Trust-Chain Etabliert"]

L -->|"10. XPub Extrahieren"| M["Sparrow Signer aufgesetzt"]

M -->|"11. Für anderen key Holder VM wdh."| H

M -->|"12. USB auf Hot-Wallet mounten"| N["Key Holder A"]

N -->|"13. XPub Extrahieren"| O["Sparrow Signer aufgesetzt"]