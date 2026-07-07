%%{init: {"flowchart": {"defaultRenderer": "elk"}}}%%
flowchart TB

  subgraph SEAL["Versiegelung — einmalig bei Initialisierung"]
    direction TB
    ENT["Entropie erzeugen"]
    MN["24-Wort-Mnemonik<br/>physisch notieren (> 128 Byte, nicht TPM-versiegelbar)"]
    SE["Entropie an PCR binden<br/>und im TPM versiegeln"]
    ENT --> MN
    ENT --> SE
  end

  subgraph UNSEAL["Entsiegelung — bei jedem Signiervorgang"]
    direction TB
    BOOT["Boot: aktuellen Zustand in<br/>PCR messen"]
    POL["Policy-Session lädt aktuelle PCR"]
    CMP("PCR == versiegelter Zustand?")
    OK["Entropie entsiegeln →<br/>Key A nur im RAM ableiten →<br/>signieren → Geheimnisse löschen"]
    FAIL["Entsiegelung schlägt fehl →<br/>Key A nicht verfügbar"]
    BOOT --> POL --> CMP
    CMP -->|"ja"| OK
    CMP -->|"nein"| FAIL
  end

  SE -.->|"versiegeltes Geheimnis"| BOOT
  REBUILD["nixos rebuild / switch<br/>entfernt/ändert Härtung"] -->|"verändert künftigen PCR-Zustand"| BOOT
  FAIL -.->|"Rollback auf früheren Build<br/>oder Neu-Setup mit notierter Seed"| REC["Wiederherstellung"]

  classDef bad fill:#ffd9d9,stroke:#c0392b;
  classDef good fill:#d9f2d9,stroke:#27ae60;
  class OK good; class FAIL bad;