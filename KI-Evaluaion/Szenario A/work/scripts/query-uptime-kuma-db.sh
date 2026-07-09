#!/usr/bin/env bash
set -euo pipefail

pct exec 203 -- sh -lc 'docker exec ops-uptime-kuma-1 node - <<'"'"'NODE'"'"'
const Database = require("better-sqlite3");
const db = new Database("/app/data/kuma.db", { readonly: true });

function single(sql) {
  return db.prepare(sql).get();
}

const users = single("select count(*) as c from user").c;
const monitors = single("select count(*) as c from monitor").c;
const notifications = single("select count(*) as c from notification").c;
const settings = db.prepare("select key, value from setting where key in ('serverTimezone', 'entryPage')").all();

console.log(JSON.stringify({ users, monitors, notifications, settings }, null, 2));
NODE'
