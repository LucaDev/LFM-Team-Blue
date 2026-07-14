#!/usr/bin/env bash
set -euo pipefail

pct exec 203 -- sh -lc "docker exec ops-uptime-kuma-1 node -e 'const Database = require(\"better-sqlite3\"); const db = new Database(\"/app/data/kuma.db\", { readonly: true }); const row = (sql) => db.prepare(sql).get(); const data = { users: row(\"select count(*) as c from user\").c, monitors: row(\"select count(*) as c from monitor\").c, notifications: row(\"select count(*) as c from notification\").c }; console.log(JSON.stringify(data));'"
