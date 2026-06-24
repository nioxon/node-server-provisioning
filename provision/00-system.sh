#!/usr/bin/env bash
set -e
apt update -y
apt upgrade -y
apt install -y software-properties-common unzip zip curl ca-certificates \
  nano vim net-tools lsof iputils-ping dnsutils findmnt
