flowchart TD

A["User Request / Event Trigger"]

A -->|"1. TX-Anfrage"| B["Middleware"]

B -->|"2. UTXO-Abfrage"| C["Bitcoin Core"]

C -->|"3. UTXOs + Kosten Schätzung"| B

B -->|"4. Erzeuge TX-Intent"| D["OPA"]

D -->|"5. Policy Bestätigung"| B

B -->|"6. Übergabe TX-Parameter"| E["Transaction Builder"]

E -->|"7. unsignierte PSBT"| B

B -->|"8. unsignierte PSBT"| F["Signierer"]

F -->|"9. Signatur key A"| F

F -->|"10. PSBT 1/x"| B

B -->|"C) 11. PSBT 1/3"| I["USB"]

B -->|"H) 11. PSBT 1/1"| C

C -->|"H) 12. Broadcast"| J["Bitcoin Netzwerk"]



oder
flowchart TD

A["User Request / Event Trigger"]

A -->|"1. TX-Anfrage"| B["Middleware"]

B -->|"2. UTXO-Abfrage"| C["Bitcoin Core"]

C -->|"3. UTXOs + Gebühren-Schätzung"| B

B -->|"4. TX-Intent"| D["OPA"]

D -->|"5. Policy Approval"| B

B -->|"6. TX-Parameter"| E["Transaction Builder"]

E -->|"7. Unsignierte PSBT"| B

B -->|"8. PSBT an Signierer"| F["Key A Signierer"]

F -->|"9. Bitcoin-Signatur mit Key A"| G["PSBT 1/3"]

%% Cold Wallet Pfad

G -->|"10A. Betrag > Hot-Limit"| H["USB Export"]

H -->|"11A. PSBT 1/3"| I["Cold Wallet Workflow"]

%% Hot Wallet Pfad

G -->|"10B. Betrag ≤ Hot-Limit"| J["Finalisierung"]

J -->|"11B. Finale Bitcoin-Transaktion"| C

C -->|"12B. Broadcast"| K["Bitcoin Network"]