# Talos Download

talos Download via Talos Image Factory
Einstellungen:
Bare Metal
Version: 1.13.0 (oder neuer aber ungetestet)
Secureboot AN
UEFI Boot

Link zu der Konfiguration:
https://factory.talos.dev/?arch=amd64&bootloader=sd-boot&cmdline-set=true&extensions=-&extensions=siderolabs%2Fgvisor&extensions=siderolabs%2Fkata-containers&extensions=siderolabs%2Fqemu-guest-agent&platform=metal&secureboot=true&target=metal&version=1.13.0

Download Direkt aus Proxmox heraus storage -> ISO Images -> Download from URL
Download URL: https://factory.talos.dev/image/1d9b01f30f1822446f7f123b3f2d95bffb99b9cad3467807a9308408b58dedda/v1.13.0/metal-amd64-secureboot.iso

```
downloading https://factory.talos.dev/image/1d9b01f30f1822446f7f123b3f2d95bffb99b9cad3467807a9308408b58dedda/v1.13.0/metal-amd64-secureboot.iso to /var/lib/vz/template/iso/metal-amd64-secureboot.iso
--2026-05-03 11:09:55--  https://factory.talos.dev/image/1d9b01f30f1822446f7f123b3f2d95bffb99b9cad3467807a9308408b58dedda/v1.13.0/metal-amd64-secureboot.iso
Resolving factory.talos.dev (factory.talos.dev)... 131.153.154.51
Connecting to factory.talos.dev (factory.talos.dev)|131.153.154.51|:443... connected.
HTTP request sent, awaiting response... 302 Found
Location: https://assets.factory.talos.dev/assets/c6295f6eb0d7e7f5e86515e033ce155ea8a912312258a19a62ca182dac553c23?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=4cb9c5618e2681ac12b61dd0303523b2%2F20260503%2FENAM%2Fs3%2Faws4_request&X-Amz-Date=20260503T090957Z&X-Amz-Expires=3600&X-Amz-SignedHeaders=host&response-content-disposition=attachment%3B%20filename%3D%22metal-amd64-secureboot.iso%22&X-Amz-Signature=2e73617bb3cbeedeba2d69eec2da797ab18f18a66eb988bf40053da57d321134 [following]
--2026-05-03 11:09:57--  https://assets.factory.talos.dev/assets/c6295f6eb0d7e7f5e86515e033ce155ea8a912312258a19a62ca182dac553c23?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=4cb9c5618e2681ac12b61dd0303523b2%2F20260503%2FENAM%2Fs3%2Faws4_request&X-Amz-Date=20260503T090957Z&X-Amz-Expires=3600&X-Amz-SignedHeaders=host&response-content-disposition=attachment%3B%20filename%3D%22metal-amd64-secureboot.iso%22&X-Amz-Signature=2e73617bb3cbeedeba2d69eec2da797ab18f18a66eb988bf40053da57d321134
Resolving assets.factory.talos.dev (assets.factory.talos.dev)... 2606:4700:10::ac42:946e, 2606:4700:10::6814:2384, 172.66.148.110, ...
Connecting to assets.factory.talos.dev (assets.factory.talos.dev)|2606:4700:10::ac42:946e|:443... connected.
HTTP request sent, awaiting response... 200 OK
Length: 687124480 (655M) [application/x-iso9660-image]
Saving to: '/var/lib/vz/template/iso/metal-amd64-secureboot.iso.tmp_dwnl.214801'
     0K ........ ........ ........ ........  4% 33.4M 19s
 32768K ........ ........ ........ ........  9% 14.6M 29s
 65536K ........ ........ ........ ........ 14% 14.3M 31s
 98304K ........ ........ ........ ........ 19% 19.8M 29s
131072K ........ ........ ........ ........ 24%  118M 23s
163840K ........ ........ ........ ........ 29% 95.0M 18s
196608K ........ ........ ........ ........ 34%  108M 15s
229376K ........ ........ ........ ........ 39% 87.7M 13s
262144K ........ ........ ........ ........ 43% 97.7M 11s
294912K ........ ........ ........ ........ 48% 95.6M 9s
327680K ........ ........ ........ ........ 53% 98.8M 8s
360448K ........ ........ ........ ........ 58% 97.0M 7s
393216K ........ ........ ........ ........ 63% 98.9M 6s
425984K ........ ........ ........ ........ 68% 97.4M 5s
458752K ........ ........ ........ ........ 73%  112M 4s
491520K ........ ........ ........ ........ 78% 41.8M 3s
524288K ........ ........ ........ ........ 83% 92.1M 2s
557056K ........ ........ ........ ........ 87% 93.2M 2s
589824K ........ ........ ........ ........ 92%  102M 1s
622592K ........ ........ ........ ........ 97% 99.9M 0s
655360K ........ .......                   100%  120M=13s
2026-05-03 11:10:11 (51.4 MB/s) - '/var/lib/vz/template/iso/metal-amd64-secureboot.iso.tmp_dwnl.214801' saved [687124480/687124480]
download of 'https://factory.talos.dev/image/1d9b01f30f1822446f7f123b3f2d95bffb99b9cad3467807a9308408b58dedda/v1.13.0/metal-amd64-secureboot.iso' to '/var/lib/vz/template/iso/metal-amd64-secureboot.iso' finished
TASK OK
```

In Proxmox:
Neue VM
General:
Advanced anhaken
Tags: k8s hinzufügen
Name k8s-01

OS:
Heruntergeladenes ISO Image auswählen

System:
Machine: q35
BIOS: OVMF (UEFI)
Pre enroll keys: NEIN
Add EFI Disk: YES
Add TPM: YES
QEMU Agent: YES

Disk:
Size: 50Gi
SSD Emulation: YES
Type: VirtIO SCSI (nicht VirtIO SCSI single!)

CPU:
Cores: 4
Type: host

Memory:
Size: 16384Mi
Balloning Device: No

Network:
Individuell (in unserem fall vmbr1)

Optional: VirtIO RNG Device hinzufügen für bessere entropie

Erstellen, dann 2x Klonen (k8s-02 und k8s-03)

TalosCTL downloaden: https://docs.siderolabs.com/talos/v1.13/getting-started/talosctl

macos via brew: brew install siderolabs/tap/talosctl
linux: curl -sL https://talos.dev/install | sh

machinen statische IP zuweisen (via DHCP)
In unserem Fall
192.168.99.150 - 192.168.99.152 (machinen ggf. neustarten damit sie die IP annehmen. Siehe IP oben rechts)

Alternativ: auch mit DNS ansprechbar, wenn lokales DNS eingerichtet ist

talosctl gen config k8s-cluster https://192.168.99.150:6443 --output-dir machineconfig -t talosconfig,controlplane --install-image factory.talos.dev/installer/1d9b01f30f1822446f7f123b3f2d95bffb99b9cad3467807a9308408b58dedda:v1.13.0 --config-patch @patch/cluster.yaml

talosctl apply-config --insecure --nodes 192.168.99.150,192.168.99.151,192.168.99.152 --file machineconfig/controlplane.yaml

```
LFM-Team-Blue/k8s/talos on  k8s [?] ❯ talosctl apply-config --insecure --nodes 192.168.99.150,192.168.99.151,192.168.99.152 --file machineconfig/controlplane.yaml
Applied configuration without a reboot
```

Konsolen der Nodes: wechselt von maintenance auf installing. Machinen starten neu. CD Laufwerk entfernen oder ISO auswerfen

Stage wechselt auf Booting. Danch cluster initial initialisieren

```
export TALOSCONFIG="machineconfig/talosconfig"
talosctl config endpoint 192.168.99.150
talosctl config node 192.168.99.150
talosctl bootstrap
```

Stage wechselt auf Running, Ready wechselt auf true
Alle Komponenten wechseln auf Healthy. Erst auf der ersten, dann auf allen Nodes

Das Bootstrapping ist nun vollendet

Kubeconfig holen:
talosctl kubeconfig machineconfig/

export KUBECONFIG="$(pwd)/machineconfig/kubeconfig"
