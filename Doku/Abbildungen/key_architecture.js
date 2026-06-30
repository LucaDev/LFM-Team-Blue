%%{init: {"flowchart": {"defaultRenderer": "elk"}}}%%
flowchart TB

  KA["Key A · Hot-VM (TPM-versiegelt)"]
  KB["Key B · Cold Key-B-VM"]
  KC["Key C · Cold Key-C-VM (Recovery)"]

  HOT["Hot-Wallet<br/>Single-Signature (1 Signatur)"]
  COLD["Cold-Wallet<br/>2-aus-3-Multi-Signatur (2 Signaturen)"]

  KA -->|"signiert allein"| HOT
  KA -.->|"Cosigner"| COLD
  KB -.->|"Cosigner"| COLD
  KC -.->|"Cosigner"| COLD

  subgraph COMBOS["Gültige 2-aus-3-Signaturkombinationen"]
    direction TB
    AB["A + B  —  Normalfall (Hot signiert 1/3, Key B ergänzt)"]
    AC["A + C  —  Alternative / Recovery-Cosigner"]
    BC["B + C  —  rein Cold, ohne Hot-Beteiligung"]
  end
  COLD --> COMBOS

  classDef dual fill:#ffe8c2,stroke:#d08700,stroke-width:2px;
  class KA dual;