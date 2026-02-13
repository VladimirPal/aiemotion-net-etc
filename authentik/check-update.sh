#!/bin/bash
set -e

LOCAL_VERSION=$("$(dirname "$0")/version.sh")
LATEST_VERSION=$(curl -s https://api.github.com/repos/goauthentik/authentik/releases/latest | jq -r .tag_name)
LATEST_VERSION=${LATEST_VERSION#version/}

printf "Local version: %s\n" "$LOCAL_VERSION"
printf "Latest version: %s\n" "$LATEST_VERSION"
if [[ "$LOCAL_VERSION" != "$LATEST_VERSION" && -n "$LATEST_VERSION" ]]; then
  echo "UPDATE AVAILABLE: $LATEST_VERSION"
else
  echo "UP TO DATE"
fi
