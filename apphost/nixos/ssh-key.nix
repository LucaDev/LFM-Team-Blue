# SSH Public Key(s) für den Login als "apphost"-Nutzer.
#
# Automatisch von nixos/install.sh gesetzt (der Key wird während der
# Installation interaktiv abgefragt). Nachträglich änderbar durch Bearbeiten dieser Datei und anschließendes:
# >  sudo nixos-rebuild switch --flake /opt/apphost#apphost
[
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILjUx5YA3RwdM0xfXY7KMZb3N3BrK1tDyJ/qcQQvBWJE luca@Laptop-von-Luca.local"
]
