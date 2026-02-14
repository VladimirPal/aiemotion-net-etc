#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/repo"
DOCKERFILE_ORIGINAL="$REPO_DIR/docker/Dockerfile"
DOCKERFILE_EXTENDED="$SCRIPT_DIR/Dockerfile"

IMAGE_NAME="${1:-it-pal/synapse:latest}"
BUILD_CONTEXT="$REPO_DIR"
ORIGINAL_IMAGE="synapse-original:latest"

echo "Building original Dockerfile from synapse repo (builds all stages)..."
DOCKER_BUILDKIT=1 docker build \
  -f "$DOCKERFILE_ORIGINAL" \
  -t "$ORIGINAL_IMAGE" \
  "$BUILD_CONTEXT"

echo "Building extended Dockerfile with dev tools..."
docker build \
  -f "$DOCKERFILE_EXTENDED" \
  -t "$IMAGE_NAME" \
  "$SCRIPT_DIR"

echo "Built: $IMAGE_NAME"
