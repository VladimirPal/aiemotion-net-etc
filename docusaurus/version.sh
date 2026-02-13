#!/bin/bash

/etc/control/scs/bin/cli.sh exec docusaurus-builder \
  npm run --silent docusaurus -- --version
