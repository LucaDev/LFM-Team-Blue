process.chdir("/app");

const Database = require("/app/server/database");
const passwordHash = require("/app/server/password-hash");
const { R } = require("/app/node_modules/redbean-node");

const username = process.env.UPTIME_KUMA_ADMIN_USER;
const password = process.env.UPTIME_KUMA_ADMIN_PASSWORD;

if (!username || !password) {
  throw new Error("UPTIME_KUMA_ADMIN_USER and UPTIME_KUMA_ADMIN_PASSWORD are required");
}

const monitorDefaults = {
  type: "http",
  active: true,
  interval: 60,
  retryInterval: 30,
  resendInterval: 0,
  maxretries: 1,
  timeout: 30,
  ignoreTls: false,
  upsideDown: false,
  packetSize: 56,
  expiryNotification: false,
  maxredirects: 10,
  dns_resolve_type: "A",
  dns_resolve_server: "1.1.1.1",
  method: "GET",
  httpBodyEncoding: "json",
  kafkaProducerBrokers: [],
  kafkaProducerSaslOptions: {
    mechanism: "None",
  },
  kafkaProducerSsl: false,
  kafkaProducerAllowAutoTopicCreation: false,
  gamedigGivenPortOnly: true,
};

const monitors = [
  { name: "Homepage", url: "http://10.10.10.10:3000", accepted_statuscodes: [ "200-299" ] },
  { name: "Vaultwarden", url: "http://10.10.10.10:8080", accepted_statuscodes: [ "200-299" ] },
  { name: "Linkding", url: "http://10.10.10.10:9090", accepted_statuscodes: [ "200-399" ] },
  { name: "Miniflux", url: "http://10.10.10.10:8081", accepted_statuscodes: [ "200-299" ] },
  { name: "Paperless", url: "http://10.10.10.10:8000", accepted_statuscodes: [ "200-399" ] },
  { name: "Stirling PDF", url: "http://10.10.10.10:8082", accepted_statuscodes: [ "200-399", "401" ] },
  { name: "Gitea", url: "http://10.10.10.10:3001", accepted_statuscodes: [ "200-299" ] },
  { name: "Actual Budget", url: "http://10.10.10.10:5006", accepted_statuscodes: [ "200-299" ] },
  { name: "File Browser", url: "http://10.10.10.10:8083", accepted_statuscodes: [ "200-299" ] },
  { name: "Grafana", url: "http://10.10.20.20:3000", accepted_statuscodes: [ "200-399" ] },
  { name: "Uptime Kuma", url: "http://10.10.20.20:3001", accepted_statuscodes: [ "200-399" ] },
  { name: "Prometheus Ready", url: "http://10.10.20.20:9090/-/ready", accepted_statuscodes: [ "200-299" ] },
  { name: "Alertmanager", url: "http://10.10.20.20:9093", accepted_statuscodes: [ "200-299" ] },
  { name: "Loki Ready", url: "http://10.10.20.20:3100/ready", accepted_statuscodes: [ "200-299" ] },
  { name: "Blackbox Exporter", url: "http://10.10.20.20:9115", accepted_statuscodes: [ "200-299" ] },
];

function normalizeMonitorDefinition(monitor) {
  return {
    ...monitorDefaults,
    ...monitor,
  };
}

function toMonitorBeanPayload(monitor) {
  return {
    name: monitor.name,
    active: monitor.active !== false ? 1 : 0,
    interval: monitor.interval,
    url: monitor.url,
    type: monitor.type,
    maxretries: monitor.maxretries,
    ignore_tls: monitor.ignoreTls ? 1 : 0,
    upside_down: monitor.upsideDown ? 1 : 0,
    maxredirects: monitor.maxredirects,
    accepted_statuscodes_json: JSON.stringify(monitor.accepted_statuscodes),
    dns_resolve_type: monitor.dns_resolve_type,
    dns_resolve_server: monitor.dns_resolve_server,
    retry_interval: monitor.retryInterval,
    resend_interval: monitor.resendInterval,
    method: monitor.method,
    expiry_notification: monitor.expiryNotification ? 1 : 0,
    packet_size: monitor.packetSize,
    http_body_encoding: monitor.httpBodyEncoding,
    timeout: monitor.timeout,
    kafka_producer_brokers: JSON.stringify(monitor.kafkaProducerBrokers),
    kafka_producer_sasl_options: JSON.stringify(monitor.kafkaProducerSaslOptions),
    kafka_producer_ssl: monitor.kafkaProducerSsl ? 1 : 0,
    kafka_producer_allow_auto_topic_creation: monitor.kafkaProducerAllowAutoTopicCreation ? 1 : 0,
    gamedig_given_port_only: monitor.gamedigGivenPortOnly ? 1 : 0,
  };
}

async function main() {
  Database.init({
    "data-dir": "/app/data/",
  });
  await Database.connect(false, true, true);

  try {
    const existingUsers = await R.count("user");
    const existingMonitors = await R.count("monitor");

    if (existingUsers !== 0 || existingMonitors !== 0) {
      console.log("uptime-kuma already initialized");
      return;
    }

    const user = R.dispense("user");
    user.username = username;
    user.password = passwordHash.generate(password);
    user.active = 1;
    await R.store(user);

    for (const rawMonitor of monitors) {
      const monitor = normalizeMonitorDefinition(rawMonitor);
      const bean = R.dispense("monitor");

      Object.assign(bean, toMonitorBeanPayload(monitor));
      bean.user_id = user.id;

      if (typeof bean.validate === "function") {
        bean.validate();
      }

      await R.store(bean);
    }

    console.log(`uptime-kuma initialized with ${monitors.length} monitors`);
  } finally {
    await Database.close();
  }
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
