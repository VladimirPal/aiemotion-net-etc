#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/repo"
DOCKERFILE_ORIGINAL="$REPO_DIR/Dockerfile"
DOCKERFILE_EXTENDED="$SCRIPT_DIR/Dockerfile"

IMAGE_NAME="${1:-it-pal/mas:latest}"
BUILD_CONTEXT="$REPO_DIR"
ORIGINAL_IMAGE="mas-original:latest"

##
# Resource controls / knobs (all overrideable via env)
#
# This repo's release profile enables fat LTO + codegen-units=1, and the upstream
# Dockerfile cross-builds both amd64+arm64 in one go. That can easily consume all
# host RAM via parallel rustc processes.
#
# Defaults below aim to keep dev builds from freezing the machine.
##
export DOCKER_BUILDKIT="${DOCKER_BUILDKIT:-1}"

# Note: On most modern Docker installs, `docker build` is routed to
# `docker buildx build` (BuildKit). Buildx does NOT support `--memory`,
# `--memory-swap`, or `--cpus` flags, so we can't hard-cap host resources from
# here reliably.
#
# To avoid host lockups, we instead reduce peak memory by controlling the Rust
# build (jobs/LTO/targets) via build args below.
#
# Optional: increase shared memory (some toolchains use /dev/shm).
DOCKER_BUILD_SHM_SIZE="${DOCKER_BUILD_SHM_SIZE-}"

# Limit Rust/Cargo parallelism and reduce peak memory in release builds.
CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-2}"
CARGO_PROFILE_RELEASE_LTO="${CARGO_PROFILE_RELEASE_LTO:-false}"
CARGO_PROFILE_RELEASE_CODEGEN_UNITS="${CARGO_PROFILE_RELEASE_CODEGEN_UNITS:-16}"

# Build only the host arch by default (you can override to include both).
# Valid values are Rust target triples separated by spaces.
case "$(uname -m)" in
x86_64) DEFAULT_MAS_BUILD_TARGETS="x86_64-unknown-linux-gnu" ;;
aarch64 | arm64) DEFAULT_MAS_BUILD_TARGETS="aarch64-unknown-linux-gnu" ;;
*)
  # Fallback: keep upstream behavior (both)
  DEFAULT_MAS_BUILD_TARGETS="x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu"
  ;;
esac
MAS_BUILD_TARGETS="${MAS_BUILD_TARGETS:-$DEFAULT_MAS_BUILD_TARGETS}"

echo "Building original Dockerfile once (builds all stages)..."
docker_args_original=(
  -f "$DOCKERFILE_ORIGINAL"
  -t "$ORIGINAL_IMAGE"
  --ulimit memlock=8000000:8000000
  --ulimit nofile=65536:65536
)
if [ -n "$DOCKER_BUILD_SHM_SIZE" ]; then
  docker_args_original+=(--shm-size "$DOCKER_BUILD_SHM_SIZE")
fi
docker_args_original+=(
  --build-arg MAS_BUILD_TARGETS="$MAS_BUILD_TARGETS"
  --build-arg CARGO_BUILD_JOBS="$CARGO_BUILD_JOBS"
  --build-arg CARGO_PROFILE_RELEASE_LTO="$CARGO_PROFILE_RELEASE_LTO"
  --build-arg CARGO_PROFILE_RELEASE_CODEGEN_UNITS="$CARGO_PROFILE_RELEASE_CODEGEN_UNITS"
  "$BUILD_CONTEXT"
)
docker build "${docker_args_original[@]}"

echo "Building extended Dockerfile with SSH support..."
docker_args_extended=(
  -f "$DOCKERFILE_EXTENDED"
  -t "$IMAGE_NAME"
  --ulimit memlock=8000000:8000000
  --ulimit nofile=65536:65536
)
if [ -n "$DOCKER_BUILD_SHM_SIZE" ]; then
  docker_args_extended+=(--shm-size "$DOCKER_BUILD_SHM_SIZE")
fi
docker_args_extended+=("$SCRIPT_DIR")
docker build "${docker_args_extended[@]}"

echo "Built: $IMAGE_NAME"
