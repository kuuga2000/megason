#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"
HOST_USER_ID=$(id -u)
HOST_GROUP_ID=$(id -g)

docker compose run --rm \
    -e HOST_USER_ID="$HOST_USER_ID" \
    -e HOST_GROUP_ID="$HOST_GROUP_ID" \
    phpfpm sh /var/www/html/install-magento.sh
docker compose up -d phpfpm nginx varnish
