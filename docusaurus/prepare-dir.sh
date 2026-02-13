#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with root privileges"
    echo "Please run with: sudo $0"
    exit 1
fi

DOCUSAURUS_DIR="$(cd "$(dirname "$0")" && pwd)"
USER_NAME=$(id -un)

if ! getent group docusaurus >/dev/null 2>&1; then
    echo "Creating docusaurus group..."
    groupadd docusaurus
else
    echo "docusaurus group already exists"
fi

if id nginx >/dev/null 2>&1; then
    if ! groups nginx | grep -q docusaurus; then
        echo "Adding nginx to docusaurus group..."
        usermod -aG docusaurus nginx
    else
        echo "nginx is already a member of docusaurus group"
    fi
else
    echo "nginx user does not exist, skipping nginx group assignment"
fi

if ! groups "$USER_NAME" | grep -q docusaurus; then
    echo "Adding $USER_NAME to docusaurus group..."
    usermod -aG docusaurus "$USER_NAME"
else
    echo "$USER_NAME is already a member of docusaurus group"
fi

if ! groups root | grep -q docusaurus; then
    echo "Adding root to docusaurus group..."
    usermod -aG docusaurus root
else
    echo "root is already a member of docusaurus group"
fi

echo "Setting ownership and permissions..."
chown -R root:docusaurus "$DOCUSAURUS_DIR"
chmod -R 770 "$DOCUSAURUS_DIR"
chmod g+s "$DOCUSAURUS_DIR"
chmod -R g+w "$DOCUSAURUS_DIR"

echo "Directory preparation completed successfully!"
