#@ssh host=root.aiemotion.net

#@group "Preflight"

#@step "Test SSH connection to target host"
whoami
hostname
uname -a

#@step "Check package manager and existing Docker binaries (Debian only)"
if command -v apt-get >/dev/null 2>&1; then
  echo "Package manager: apt-get"
else
  echo "Unsupported package manager (Debian requires apt-get)"
  exit 1
fi

if command -v docker >/dev/null 2>&1; then
  echo "docker already present: $(docker --version)"
else
  echo "docker is not installed yet"
fi

#@group "Install Docker"

#@step "Install Docker packages"
apt-get update -y
apt-get install -y docker.io docker-cli containerd

if ! command -v docker >/dev/null 2>&1; then
  echo "docker CLI not found after install (expected /usr/bin/docker)"
  exit 1
fi
docker --version

#@step "Install and verify Docker Compose plugin"
if docker compose version >/dev/null 2>&1; then
  echo "docker compose already present: $(docker compose version)"
else
  echo "Installing docker-compose (Debian package)..."
  apt-get install -y docker-compose
fi

if docker compose version >/dev/null 2>&1; then
  docker compose version
elif command -v docker-compose >/dev/null 2>&1; then
  docker-compose version
else
  echo "Docker Compose install failed"
  exit 1
fi

#@step "Install and verify Docker Buildx plugin"
if docker buildx version >/dev/null 2>&1; then
  echo "docker buildx already present: $(docker buildx version)"
else
  echo "Installing docker buildx plugin..."
  apt-get install -y docker-buildx-plugin
fi

if ! docker buildx version >/dev/null 2>&1; then
  echo "docker buildx install failed"
  exit 1
fi
docker buildx version

#@step "Enable and start Docker service"
if ! command -v systemctl >/dev/null 2>&1; then
  echo "systemctl is required to manage docker service on this host."
  exit 1
fi
systemctl enable --now docker
systemctl restart docker
systemctl status docker --no-pager

#@group "Manage Docker"

#@step "Show Docker service and runtime info"
systemctl is-enabled docker || true
systemctl is-active docker || true
docker info

#@step "Run hello-world container smoke test"
docker run --rm hello-world

#@step "List containers, images, volumes, and networks"
docker ps -a
docker images
docker volume ls
docker network ls

#@step "Stop and remove all containers (safe if none exist)"
container_ids="$(docker ps -aq)"
if [ -n "$container_ids" ]; then
  docker stop $container_ids || true
  docker rm $container_ids
else
  echo "No containers to stop/remove."
fi

#@step "Prune unused Docker resources (requires confirmation)"
#@env CONFIRM=0
CONFIRM="${CONFIRM-0}"
if [ "$CONFIRM" != "1" ]; then
  echo "Refusing prune without CONFIRM=1"
  echo "Re-run with CONFIRM=1 to execute: docker system prune -af --volumes"
  exit 1
fi
docker system prune -af --volumes
