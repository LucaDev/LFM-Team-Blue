flowchart TD

subgraph HOT["Trust Zone 1 - Hot Environment (Internet Exposed)"]

A["Bitcoin Core"]
B["Middleware"]
C["OPA"]
D["TX Builder"]
E["Signer"]
F["Key A"]

A --> B
B --> C
C --> D
D --> E
E --> F

end

subgraph TRANSFER["Trust Zone 2 - Transfer Boundary"]

G["USB Medium"]
H["PSBT"]
I["Hash Artefakt"]

G --> H
H --> I

end

subgraph COLD["Trust Zone 3 - Cold Environment (Air-Gapped)"]

J["Koordinator"]
K["Key Holder B"]
L["Key Holder C"]

J --> K
K --> L

end

F -->|"PSBT"| G

I -->|"Import"| J   q