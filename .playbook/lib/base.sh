#!/usr/bin/env bash

# Shared helpers for playbook steps.
# Intended to be sourced by step scripts like `os/disk.sh`.

# Ensure a usable PATH in non-interactive shells.
if [ -z "${PATH-}" ]; then
  PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  export PATH
fi

need() {
  cmd="$1"
  hint="${2-}"
  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi

  for candidate in \
    "/usr/local/bin/$cmd" \
    "/usr/bin/$cmd" \
    "/bin/$cmd" \
    "/usr/sbin/$cmd" \
    "/sbin/$cmd"; do
    if [ -x "$candidate" ]; then
      candidate_dir="${candidate%/*}"
      export PATH="$candidate_dir:$PATH"
      return 0
    fi
  done

  echo "$cmd not found on PATH"
  if [ -n "$hint" ]; then
    echo "$hint"
  fi
  exit 1
}

opt() { command -v "$1" >/dev/null 2>&1; }

install_packages() {
  [ "$#" -gt 0 ] || {
    echo "install_packages: provide at least one package name"
    exit 1
  }

  if opt dnf; then
    dnf install -y "$@"
  elif opt pacman; then
    pacman -S --noconfirm "$@"
  elif opt apt-get; then
    apt-get update -y
    apt-get install -y "$@"
  elif opt apt; then
    apt update -y
    apt install -y "$@"
  else
    echo "Unsupported package manager (need dnf, pacman, apt-get, or apt) to install: $*"
    exit 1
  fi
}

ensure_cmd_installed() {
  cmd="$1"
  package="${2-$cmd}"
  label="${3-$cmd}"

  [ -n "$cmd" ] || {
    echo "ensure_cmd_installed: missing command name"
    exit 1
  }

  if opt "$cmd"; then
    echo "ok: $label already installed ($(command -v "$cmd"))"
    return 0
  fi

  install_packages "$package"
  opt "$cmd" || {
    echo "$label installation reported success but '$cmd' is still missing on PATH."
    exit 1
  }
  echo "ok: $label installed ($(command -v "$cmd"))"
}

confirm_or_exit() {
  CONFIRM="${CONFIRM-}"
  [ "$CONFIRM" = "1" ] || {
    echo "Refusing to delete without CONFIRM=1"
    echo "Tip: re-run with DRY_RUN=0 CONFIRM=1 to actually delete."
    exit 1
  }
}

dry_run() {
  default="${DRY_RUN_DEFAULT-1}"
  [ "${DRY_RUN-$default}" != "0" ]
}
