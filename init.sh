#!/bin/sh
set -e

# Start RabbitMQ in the background
rabbitmq-server &
RABBIT_PID=$!

# Wait until the node is fully up
until rabbitmqctl await_startup 2>/dev/null; do
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
