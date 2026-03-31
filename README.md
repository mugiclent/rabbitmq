# katisha — rabbitmq

RabbitMQ 4 message broker for the Katisha platform, running on `katisha-net`.
Exchanges, queues, and bindings are pre-declared via `definitions.json` and
loaded on every boot — the topology is always in sync with the repo.

Management UI available at `https://rabbitmq.katisha.online`.

---

## Topology (from CLAUDE.md)

| Exchange | Type | Queue | Routing key | Consumer |
|---|---|---|---|---|
| `notifications` | topic | `sms` | `sms.notifications` | notification-service |
| `notifications` | topic | `mail` | `mail.notifications` | notification-service |
| `notifications` | topic | `push` | `push.notifications` | push-worker |
| `logs` | topic | `audit` | `audit.logs` | audit-service |

**Never create new exchanges** — all services must publish to `notifications` or `logs`.

---

## Repository layout

```
rabbitmq/
├── Dockerfile
├── docker-compose.yml
├── config/
│   ├── rabbitmq.conf       # memory limits, disk alarms, logging
│   ├── definitions.json    # exchanges, queues, bindings — loaded on every boot
│   └── enabled_plugins     # management UI + shovel
├── .env.example
├── actions.env
├── .github/workflows/
│   └── deploy.yml
└── README.md
```

---

## Adding a new queue or exchange

Edit `config/definitions.json`, add the exchange/queue/binding, commit and push.
RabbitMQ reloads definitions on restart — the new topology is live on the next deploy.

---

## GitHub Actions secrets

| Secret | Description |
|---|---|
| `SERVER_HOST` | Server IP or hostname |
| `SERVER_USER` | SSH username |
| `SERVER_SSH_KEY` | Private SSH key |
| `RABBITMQ_USER` | Admin username |
| `RABBITMQ_PASSWORD` | Admin password |

---

## Connecting from services

```
amqp://user:password@rabbitmq:5672/
```

Services connect by container name on `katisha-net` — no public port exposed.
Only the management UI (port 15672) is accessible via nginx at
`rabbitmq.katisha.online`.
