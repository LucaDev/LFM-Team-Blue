flowchart TD

A["USB Import"]

A -->|"1. 1/3 PSBT übertragen"| B["Koordinator"]

B -->|"2. Manuelle Überprüfung"| C["Transaktion Verifiziert"]

C -->|"3. hash Skripte ausführen"| D["PSBT hashed"]

D -->|"4. Übertragen auf Key-Holder"| E["Key Holder B"]

E -->|"5. Hash überrpüfen"| F["Unkompromittierte PSBT"]

F -->|"6. Signieren in Sparrow"| G["2/3 PSBT"]

G -->|"7. USB Übertragen auf Cold-Wallet"| H["Koordinator"]

H -->|"8. Finalisierung aus 2/3 Signaturen"| I["Finale PSBT"]

I -->|"9. Übertragen zur Hot-Wallet"| J["Hot-Wallet"]

J -->|"10. Broadcast"| K["Bitcoin Netzwerk"]