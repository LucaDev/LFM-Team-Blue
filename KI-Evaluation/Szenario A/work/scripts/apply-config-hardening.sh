#!/usr/bin/env bash
set -euo pipefail

SYNC_DIR=/root/homelab-config-sync
APP_STAGING=/root/homelab-staging/app-core
OPS_STAGING=/root/homelab-staging/ops

install -d "$APP_STAGING/config/homepage" "$OPS_STAGING"

install -m 0644 "$SYNC_DIR/app-core-docker-compose.yml" "$APP_STAGING/docker-compose.yml"
install -m 0644 "$SYNC_DIR/homepage-settings.yaml" "$APP_STAGING/config/homepage/settings.yaml"
install -m 0644 "$SYNC_DIR/homepage-bookmarks.yaml" "$APP_STAGING/config/homepage/bookmarks.yaml"
install -m 0644 "$SYNC_DIR/ops-docker-compose.yml" "$OPS_STAGING/docker-compose.yml"

pct push 202 "$SYNC_DIR/app-core-docker-compose.yml" /opt/homelab/app-core/docker-compose.yml
pct push 202 "$SYNC_DIR/homepage-settings.yaml" /opt/homelab/app-core/config/homepage/settings.yaml
pct push 202 "$SYNC_DIR/homepage-bookmarks.yaml" /opt/homelab/app-core/config/homepage/bookmarks.yaml
pct push 203 "$SYNC_DIR/ops-docker-compose.yml" /opt/homelab/ops/docker-compose.yml

pct exec 202 -- bash -lc 'cd /opt/homelab/app-core && docker compose config -q && docker compose up -d && docker compose ps'
pct exec 203 -- bash -lc 'cd /opt/homelab/ops && docker compose config -q && docker compose up -d && docker compose ps'
