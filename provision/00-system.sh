#!/usr/bin/env bash
set -e

echo "🔄 Updating system and installing base packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y --no-install-recommends software-properties-common unzip zip curl ca-certificates \
  nano vim net-tools lsof iputils-ping dnsutils findmnt
