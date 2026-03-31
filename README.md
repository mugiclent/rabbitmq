# katisha — rabbitmq

RabbitMQ 4 message broker for the Katisha platform, running on `katisha-net`.
Exchanges, queues, and bindings are pre-declared via `definitions.json` and
loaded on every boot — the topology is always in sync with the repo.

Management UI: `https://rabbitmq.katisha.online`

---

## Topology

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
├── Dockerfile                  # wraps official image, adds init.sh as CMD
├── init.sh                     # entrypoint: starts RabbitMQ, creates admin user
├── docker-compose.yml
├── config/
│   ├── rabbitmq.conf           # memory limits, disk alarms, logging, load_definitions
│   ├── definitions.json        # exchanges, queues, bindings — loaded on every boot
│   └── enabled_plugins         # rabbitmq_management, rabbitmq_shovel
├── .env.example
├── actions.env                 # GitHub Actions secrets reference (never commit real values)
└── .github/workflows/
    └── deploy.yml
```

---

## Secrets — Infisical

App credentials live in Infisical, not in GitHub Actions secrets.

| Infisical path | Key | Description |
|---|---|---|
| `katisha` project → `dev` → `/rabbitmq` | `RABBITMQ_USER` | Admin username |
| `katisha` project → `dev` → `/rabbitmq` | `RABBITMQ_PASSWORD` | Admin password |

GitHub Actions secrets hold only the server connection info and the Infisical
machine identity credentials (`SERVER_HOST`, `SERVER_USER`, `SERVER_SSH_KEY`,
`INFISICAL_CLIENT_ID`, `INFISICAL_CLIENT_SECRET`, `INFISICAL_PROJECT_ID`).

---

## Deployment

Push to `main` — GitHub Actions SSHes to the server, fetches secrets from
Infisical, and runs `docker compose up -d --build`.

**Never run `docker compose up` directly on the server.** Without going through
`infisical run`, the `RABBITMQ_USER` and `RABBITMQ_PASSWORD` env vars will be
blank and RabbitMQ will start with no admin user.

### Running locally

To start RabbitMQ locally with secrets injected from Infisical:

```bash
# 1. Authenticate with Infisical (one-time per session)
INFISICAL_TOKEN=$(infisical login \
  --method=universal-auth \
  --client-id=<INFISICAL_CLIENT_ID> \
  --client-secret=<INFISICAL_CLIENT_SECRET> \
  --domain=http://localhost:8080 \
  --plain --silent)

# 2. Start RabbitMQ with secrets injected
infisical run \
  --token="$INFISICAL_TOKEN" \
  --projectId=<INFISICAL_PROJECT_ID> \
  --env=dev \
  --path=/rabbitmq \
  --domain=http://localhost:8080 \
  -- docker compose up -d --build
```

Or for quick local dev without Infisical, copy `.env.example` to `.env` and
edit the credentials, then run `docker compose up -d --build` directly.

### Changing the admin password

Update `RABBITMQ_PASSWORD` in Infisical, then re-run the deploy pipeline.
`init.sh` calls `rabbitmqctl change_password` on every start, so the stored
password is always synced to whatever Infisical injects at runtime.

---

## How init.sh works — and why it exists

### The problem

RabbitMQ creates the default admin user (from `RABBITMQ_DEFAULT_USER` /
`RABBITMQ_DEFAULT_PASS`) only when the Mnesia database is **completely empty**
on first boot.

We also use `load_definitions` in `rabbitmq.conf` to pre-declare exchanges,
queues, and bindings from `definitions.json` on every boot. The problem is
that `load_definitions` runs during the RabbitMQ boot sequence and populates
the database (vhosts, exchanges, queues) **before** the default user
initialization check. Once the database contains any data, RabbitMQ considers
it "not fresh" and skips creating the default user entirely.

The result: fresh volume + correct `RABBITMQ_DEFAULT_USER` env var + `load_definitions`
= no users in the database, and every login attempt fails.

We first tried switching from `management.load_definitions` to `load_definitions`
(the core RabbitMQ config key), which was also suspected of wiping users not
present in the file. This did not resolve the issue — the root cause was the
timing of default user creation vs. definitions loading.

### The fix — init.sh

`init.sh` replaces the default CMD with a wrapper that:

1. Starts `rabbitmq-server` in the background.
2. Waits for the node to be fully up (`rabbitmqctl await_startup`).
3. Checks whether the admin user exists:
   - **Not found** — creates the user, grants administrator tag, sets full
     permissions on the default vhost.
   - **Found** — calls `rabbitmqctl change_password` to sync the password with
     whatever was injected at runtime (so Infisical password changes take
     effect on the next deploy without wiping the volume).
4. Hands off to the `rabbitmq-server` process via `wait`.

This approach is independent of the database initialization order — the user
is always created or synced after RabbitMQ is fully booted.

---

## Adding a new queue or exchange

Edit `config/definitions.json`, add the exchange/queue/binding, commit and
push. RabbitMQ reloads definitions on restart — the new topology is live on
the next deploy.

---

## Connecting from other services

```
amqp://<user>:<password>@rabbitmq:5672/
```

Services connect by container name on `katisha-net`. No public AMQP port is
exposed. Only the management UI (port 15672) is reachable via nginx at
`rabbitmq.katisha.online`.
