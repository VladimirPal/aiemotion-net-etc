FROM debian:bookworm-slim AS runtime

# Install OpenSSH server for remote MAS CLI execution
# api needs to SSH into this container to execute MAS CLI commands
RUN apt-get update && apt-get install -y \
  openssh-server bash curl ca-certificates \
  && rm -rf /var/lib/apt/lists/* \
  && apt-get clean

# Configure SSH server for secure key-based authentication only
# - Enable pubkey authentication (required for api to connect)
# - Disable password authentication (security best practice)
# - Configure root login via SSH keys only
RUN mkdir -p /var/run/sshd \
  && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config \
  && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config \
  && sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config \
  && echo 'Port 22' >>/etc/ssh/sshd_config \
  && echo 'AuthorizedKeysFile .ssh/authorized_keys' >>/etc/ssh/sshd_config \
  && echo 'PubkeyAuthentication yes' >>/etc/ssh/sshd_config \
  && echo 'PasswordAuthentication no' >>/etc/ssh/sshd_config \
  && echo 'PermitEmptyPasswords no' >>/etc/ssh/sshd_config

# Generate SSH host keys and create .ssh directory for root user
# The authorized_keys file will be mounted from host and copied by entrypoint.sh
RUN ssh-keygen -A && mkdir -p /root/.ssh && chmod 700 /root/.ssh

COPY --from=mas-original:latest /usr/local/bin/mas-cli /usr/local/bin/mas-cli
COPY --from=mas-original:latest /usr/local/share/mas-cli /usr/local/share/mas-cli

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /
EXPOSE 22
ENTRYPOINT ["/entrypoint.sh"]
