#!/bin/sh
set -e

# Start RabbitMQ in the background
rabbitmq-server &
RABBIT_PID=$!

# Forward SIGTERM/SIGINT to rabbitmq-server so Docker can stop it cleanly.
trap 'rabbitmqctl stop; wait $RABBIT_PID' TERM INT

# Wait until the node is fully up (60 s timeout — fail fast if something is wrong)
WAIT=0
until rabbitmqctl await_startup 2>/dev/null; do
  WAIT=$((WAIT + 2))
  if [ "$WAIT" -ge 60 ]; then
    echo "[rabbitmq] ERROR: node did not start within 60 s, aborting"
    kill "$RABBIT_PID"
    exit 1
  fi
  sleep 2
done

# Create the admin user if not already present.
# Needed because load_definitions pre-populates the DB, which causes
# RabbitMQ to skip RABBITMQ_DEFAULT_USER creation (it only runs on a
# completely empty DB).
if ! rabbitmqctl list_users 2>/dev/null | grep -qF "${RABBITMQ_DEFAULT_USER}"; then
  rabbitmqctl add_user "${RABBITMQ_DEFAULT_USER}" "${RABBITMQ_DEFAULT_PASS}"
  rabbitmqctl set_user_tags "${RABBITMQ_DEFAULT_USER}" administrator
  rabbitmqctl set_permissions -p / "${RABBITMQ_DEFAULT_USER}" ".*" ".*" ".*"
  echo "Admin user '${RABBITMQ_DEFAULT_USER}' created."
else
  # Sync the password on every start so Infisical changes take effect on restart.
  rabbitmqctl change_password "${RABBITMQ_DEFAULT_USER}" "${RABBITMQ_DEFAULT_PASS}"
  echo "Admin user '${RABBITMQ_DEFAULT_USER}' password synced."
fi

# Hand off to the RabbitMQ process
wait "$RABBIT_PID"
