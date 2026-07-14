#!/bin/bash
set -Eeuo pipefail

if ! grep -q 'BEGIN AILAB ADMIN ONION' /etc/tor/torrc; then
  cat >> /etc/tor/torrc <<'EOF'
# BEGIN AILAB ADMIN ONION
HiddenServiceDir /var/lib/tor/ssh-admin-onion
HiddenServiceVersion 3
HiddenServicePort 22 10.10.10.1:22
# END AILAB ADMIN ONION
EOF
fi

systemctl restart tor@default.service >/dev/null 2>&1 || systemctl restart tor.service >/dev/null 2>&1

for _ in $(seq 1 60); do
  [[ -f /var/lib/tor/ssh-admin-onion/hostname ]] && break
  sleep 2
done

ls -l /var/lib/tor/ssh-admin-onion
printf -- '---\n'
cat /var/lib/tor/ssh-admin-onion/hostname
