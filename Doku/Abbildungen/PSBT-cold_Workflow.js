flowchart TD

EXP["Hot-Seite: psbt_export.sh -> 1/3-PSBT auf USB"]
EXP --> USBIN["USB-Import auf Key-B-VM"]
USBIN -->|"1. PSBT 1/3 (von Key A signiert)"| KB["Key-B-VM (Koordinator + Key B)"]
KB -->|"2. PSBT importieren"| VER["Details pruefen: Output = Hot-Wallet, Betrag, Gebuehr"]
VER -->|"3. mit Key B signieren (Sparrow)"| SIG["PSBT 2/3"]
SIG -->|"4. Finalisierung auf derselben VM"| FIN["Finalisierte PSBT"]
FIN -->|"5. USB -> Hot-Wallet"| HOT["Hot-Wallet"]
HOT -->|"6. psbt_broadcast.sh -> Bitcoin Core"| NET["Bitcoin-Netzwerk"]

%% 2-of-3: alternativ Key-C-VM (Recovery) fuer die zweite Signatur
VER -.->|"alternativ: Recovery"| KC["Key-C-VM"]
KC -.-> SIG