#!/bin/bash
set -e

# Copy the mounted authorized_keys file to the correct location for SSH authentication
# This file is mounted from the host at mas/ssh/authorized_keys
# and contains the public RSA key that chronos-api uses to authenticate
if [ -f /tmp/authorized_keys ]; then
  cp /tmp/authorized_keys /root/.ssh/authorized_keys
  chmod 0600 /root/.ssh/authorized_keys
  chown root:root /root/.ssh/authorized_keys
fi

# Start SSH server in background (needed for chronos-api to execute MAS CLI commands)
/usr/sbin/sshd -D &

# Execute MAS CLI with any provided arguments
exec /usr/local/bin/mas-cli "$@"
