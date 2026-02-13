#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

cd "$SCRIPT_DIR"

service_exists() {
  local service_name="$1"
  local output
  output=$(docker compose \
    -f "$SCRIPT_DIR/docker-compose.yml" \
    ps --quiet "$service_name" 2>/dev/null)
  [ -n "$output" ]
}

wait_for_service() {
  local service_name="$1"
  local max_wait=$((60 * 10))
  local wait_time=0
    
  echo "Waiting for service '${service_name}' to start..."
  
  while ! service_exists "$service_name" && [ $wait_time -lt $max_wait ]; do
    sleep 1
    wait_time=$((wait_time + 1))
    echo "Still waiting for '${service_name}'... (${wait_time}s)"
  done
    
  if service_exists "$service_name"; then
    echo "Service '${service_name}' is now running!"
    return 0
  else
    echo "Error: Service '${service_name}' did not start within ${max_wait} seconds"
    return 1
  fi
}

show_logs_with_reconnect() {
  local services=("$@")
    
  trap 'echo "Interrupted by user, exiting..."; exit 0' INT
    
  while true; do
    echo "Connecting to logs for: ${services[*]}"
        
    docker compose \
      -f "$SCRIPT_DIR/docker-compose.yml" \
      logs -f "${services[@]}" &

    local logs_pid=$!
        
    wait $logs_pid
        
    echo "Logs command exited, waiting for services to restart..."
    sleep 2
        
    for service in "${services[@]}"; do
      if ! service_exists "$service"; then
        echo "Service '$service' is not running, waiting for it to start..."
        if ! wait_for_service "$service"; then
          echo "Error: Service '$service' failed to start"
          exit 1
        fi
      fi
    done
        
    echo "Services are running again, reconnecting..."
  done
}

if [ $# -eq 0 ]; then
  echo "No service specified, using default: server"
  if ! service_exists "server"; then
    if ! wait_for_service "server"; then
      echo "Error: Failed to start service 'server'"
      exit 1
    fi
  fi
  show_logs_with_reconnect "server"
else
  for service in "$@"; do
    if ! service_exists "$service"; then
      if ! wait_for_service "$service"; then
        echo "Error: Failed to start service '${service}'"
        exit 1
      fi
    fi
  done
  show_logs_with_reconnect "$@"
fi
