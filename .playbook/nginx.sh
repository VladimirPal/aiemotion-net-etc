#@ssh host=root.aiemotion.net

#@group "Install Nginx"

#@step "Install latest Nginx from official repository"
if ! command -v apt-get >/dev/null 2>&1; then
  echo "Unsupported package manager (Debian/Ubuntu apt-get required)"
  exit 1
fi

apt-get update -y
apt-get install -y curl gnupg2 ca-certificates lsb-release debian-archive-keyring

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://nginx.org/keys/nginx_signing.key \
  | gpg --dearmor -o /etc/apt/keyrings/nginx-archive-keyring.gpg
chmod 644 /etc/apt/keyrings/nginx-archive-keyring.gpg

codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
if [ -z "$codename" ]; then
  echo "Unable to determine distro codename from /etc/os-release"
  exit 1
fi

cat >/etc/apt/sources.list.d/nginx.list <<EOF
deb [signed-by=/etc/apt/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/mainline/debian/ $codename nginx
EOF

apt-get update -y
apt-get install -y nginx

if ! command -v nginx >/dev/null 2>&1; then
  echo "nginx binary not found after install"
  exit 1
fi
nginx -v

#@step "Enable and start Nginx service"
if ! command -v systemctl >/dev/null 2>&1; then
  echo "systemctl is required to manage nginx service on this host."
  exit 1
fi
systemctl enable --now nginx
systemctl restart nginx
systemctl status nginx --no-pager

#@group "Manage Nginx"

#@step "Show service state, version, and listening sockets"
systemctl is-enabled nginx || true
systemctl is-active nginx || true
nginx -V
ss -ltnp | rg nginx || true

#@step "Validate config then reload service"
nginx -t
systemctl reload nginx
systemctl status nginx --no-pager

#@step "Restart service safely"
systemctl restart nginx
systemctl status nginx --no-pager

#@group "Maintenance Nginx"

#@step "Upgrade Nginx to latest available package"
apt-get update -y
apt-get install -y --only-upgrade nginx
nginx -v

#@step "Inspect logs and recent service errors"
journalctl -u nginx -n 100 --no-pager || true
if [ -d /var/log/nginx ]; then
  ls -lah /var/log/nginx
fi

#@step "Run logrotate dry-run for nginx logs"
if [ -f /etc/logrotate.d/nginx ]; then
  logrotate -d /etc/logrotate.d/nginx
else
  echo "No /etc/logrotate.d/nginx found on host."
fi

#@step "Purge nginx cache files (requires confirmation)"
#@env CONFIRM=0
CONFIRM="${CONFIRM-0}"
if [ "$CONFIRM" != "1" ]; then
  echo "Refusing cache cleanup without CONFIRM=1"
  echo "Re-run with CONFIRM=1 to execute: rm -rf /var/cache/nginx/*"
  exit 1
fi

if [ -d /var/cache/nginx ]; then
  rm -rf /var/cache/nginx/*
  echo "Nginx cache cleaned."
else
  echo "/var/cache/nginx does not exist."
fi
