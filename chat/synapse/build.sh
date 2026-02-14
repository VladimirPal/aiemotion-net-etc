#!/bin/bash
REPO_DIR="/etc/chat/synapse/repo"
DOCKERFILE_ORIGINAL="/etc/chat/synapse/repo/Dockerfile"
DOCKERFILE_EXTENDED="/etc/chat/synapse/Dockerfile"

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
  "$REPO_DIR"

echo "Built: $IMAGE_NAME"
