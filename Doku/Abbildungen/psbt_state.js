---
config:
  flowchart:
    defaultRenderer: elk
  theme: redux
  look: classic
  layout: elk
---
stateDiagram
  direction TB
  [*] --> INTENT_CREATED:TX-Anfrage an API
  INTENT_CREATED --> PSBT_CREATED:TX-Builder (Bitcoin Core)
  INTENT_CREATED --> PSBT_FAILED:Bau fehlgeschlagen
  PSBT_CREATED --> OPA_APPROVED:OPA-Policy
  PSBT_CREATED --> OPA_REJECTED:OPA-Policy
  OPA_APPROVED --> SIGNED:Signatur Key A
  OPA_APPROVED --> SIGNING_FAILED:Signatur fehlgeschlagen
  SIGNED --> FINALIZED:Hot 1/1 finalisiert (finalizepsbt)
  SIGNED --> FINALIZE_FAILED:Finalisierung fehlgeschlagen
  FINALIZED --> BROADCASTED:Broadcast (sendrawtransaction)
  FINALIZED --> BROADCAST_FAILED:Broadcast fehlgeschlagen
  SIGNED --> WAITING_HUMAN:Cold 1/3
  WAITING_HUMAN --> COLD_STARTED:psbt_export.sh auf USB
  WAITING_HUMAN --> COLD_STOPPED:alte Nachbefuell-PSBT gestoppt/geloescht
  COLD_STARTED --> BROADCASTED:2/3 signiert + psbt_broadcast.sh
  BROADCASTED --> [*]
  OPA_REJECTED --> [*]
  PSBT_FAILED --> [*]
  SIGNING_FAILED --> [*]
  FINALIZE_FAILED --> [*]
  BROADCAST_FAILED --> [*]
  COLD_STOPPED --> [*]
  note right of COLD_STARTED 
  keine Abbruchbedingung;
    verbleibt als Waise, falls der Operator
    das Cold-Signing nicht abschliesst
  end note