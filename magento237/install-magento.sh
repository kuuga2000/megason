#!/bin/sh
set -eu

APP_DIR=${APP_DIR:-/var/www/html}
MAGENTO_VERSION=${MAGENTO_VERSION:-2.3.7-p4}
MAGENTO_BASE_URL=${MAGENTO_BASE_URL:-http://localhost:8082/}
MAGENTO_PUBLIC_KEY=${MAGENTO_PUBLIC_KEY:-}
MAGENTO_PRIVATE_KEY=${MAGENTO_PRIVATE_KEY:-}
MAGENTO_DB_HOST=${MAGENTO_DB_HOST:-mariadb}
MAGENTO_DB_NAME=${MAGENTO_DB_NAME:-magento237}
MAGENTO_DB_USER=${MAGENTO_DB_USER:-magento237}
MAGENTO_DB_PASSWORD=${MAGENTO_DB_PASSWORD:-magento237}
ELASTICSEARCH_HOST=${ELASTICSEARCH_HOST:-elasticsearch}
ELASTICSEARCH_PORT=${ELASTICSEARCH_PORT:-9200}
REDIS_HOST=${REDIS_HOST:-redis}
REDIS_PORT=${REDIS_PORT:-6379}
RABBITMQ_HOST=${RABBITMQ_HOST:-rabbitmq}
RABBITMQ_PORT=${RABBITMQ_PORT:-5672}
RABBITMQ_USER=${RABBITMQ_USER:-magento237}
RABBITMQ_PASSWORD=${RABBITMQ_PASSWORD:-magento237}
MAGENTO_ADMIN_USER=${MAGENTO_ADMIN_USER:-admin}
MAGENTO_ADMIN_PASSWORD=${MAGENTO_ADMIN_PASSWORD:-Admin123!Admin123!}
MAGENTO_ADMIN_EMAIL=${MAGENTO_ADMIN_EMAIL:-admin@example.com}
TZ=${TZ:-Asia/Jakarta}
HOST_USER_ID=${HOST_USER_ID:-1000}
HOST_GROUP_ID=${HOST_GROUP_ID:-1000}

cd "$APP_DIR"

if [ -f auth.json ]; then
    COMPOSER_AUTH=$(cat auth.json)
    export COMPOSER_AUTH
elif [ -n "$MAGENTO_PUBLIC_KEY" ] && [ -n "$MAGENTO_PRIVATE_KEY" ]; then
    cat > auth.json <<EOF
{
  "http-basic": {
    "repo.magento.com": {
      "username": "${MAGENTO_PUBLIC_KEY}",
      "password": "${MAGENTO_PRIVATE_KEY}"
    }
  }
}
EOF
    COMPOSER_AUTH=$(cat auth.json)
    export COMPOSER_AUTH
else
    echo "ERROR: Set MAGENTO_PUBLIC_KEY and MAGENTO_PRIVATE_KEY in megason/.env."
    exit 1
fi

# Admin notification/version checks read Composer metadata as PHP-FPM. Keep
# Marketplace credentials private while allowing the www-data group to read.
chgrp www-data auth.json
chmod 640 auth.json

if [ ! -f composer.json ]; then
    rm -rf /tmp/magento237
    COMPOSER_MEMORY_LIMIT=-1 composer-install create-project \
        --repository-url=https://repo.magento.com/ \
        "magento/project-community-edition=${MAGENTO_VERSION}" \
        /tmp/magento237
    cp -a /tmp/magento237/. "$APP_DIR"/
    rm -rf /tmp/magento237
fi

if [ ! -f bin/magento ]; then
    echo "ERROR: Magento package download failed or bin/magento is missing."
    exit 1
fi

CLEANUP_DATABASE=
if [ -f app/etc/env.php ]; then
    if php -d memory_limit=-1 bin/magento setup:db:status >/dev/null 2>&1; then
        echo "Magento already appears installed in $APP_DIR."
        exit 0
    fi
    echo "Incomplete Magento database detected; restarting setup with a clean database."
    CLEANUP_DATABASE=--cleanup-database
fi

until mysqladmin ping -h"$MAGENTO_DB_HOST" -u"$MAGENTO_DB_USER" -p"$MAGENTO_DB_PASSWORD" --silent; do
    echo "Waiting for MariaDB..."
    sleep 3
done

until curl -fsS "http://${ELASTICSEARCH_HOST}:${ELASTICSEARCH_PORT}" >/dev/null; do
    echo "Waiting for Elasticsearch..."
    sleep 3
done

php -d memory_limit=-1 bin/magento setup:install \
    $CLEANUP_DATABASE \
    --base-url="$MAGENTO_BASE_URL" \
    --db-host="$MAGENTO_DB_HOST" \
    --db-name="$MAGENTO_DB_NAME" \
    --db-user="$MAGENTO_DB_USER" \
    --db-password="$MAGENTO_DB_PASSWORD" \
    --admin-firstname=Admin \
    --admin-lastname=User \
    --admin-email="$MAGENTO_ADMIN_EMAIL" \
    --admin-user="$MAGENTO_ADMIN_USER" \
    --admin-password="$MAGENTO_ADMIN_PASSWORD" \
    --language=en_US \
    --currency=USD \
    --timezone="$TZ" \
    --use-rewrites=1 \
    --amqp-host="$RABBITMQ_HOST" \
    --amqp-port="$RABBITMQ_PORT" \
    --amqp-user="$RABBITMQ_USER" \
    --amqp-password="$RABBITMQ_PASSWORD" \
    --cache-backend=redis \
    --cache-backend-redis-server="$REDIS_HOST" \
    --cache-backend-redis-port="$REDIS_PORT" \
    --page-cache=redis \
    --page-cache-redis-server="$REDIS_HOST" \
    --page-cache-redis-port="$REDIS_PORT" \
    --session-save=redis \
    --session-save-redis-host="$REDIS_HOST" \
    --session-save-redis-port="$REDIS_PORT" \
    --backend-frontname=admin

php -d memory_limit=-1 bin/magento config:set catalog/search/engine elasticsearch7
php -d memory_limit=-1 bin/magento config:set catalog/search/elasticsearch7_server_hostname "$ELASTICSEARCH_HOST"
php -d memory_limit=-1 bin/magento config:set catalog/search/elasticsearch7_server_port "$ELASTICSEARCH_PORT"
php -d memory_limit=-1 bin/magento config:set catalog/search/elasticsearch7_index_prefix magento237
php -d memory_limit=-1 bin/magento config:set catalog/search/elasticsearch7_enable_auth 0
php -d memory_limit=-1 bin/magento deploy:mode:set developer
php -d memory_limit=-1 bin/magento setup:static-content:deploy -f en_US
./fix-static-icon-escapes.sh
php -d memory_limit=-1 bin/magento indexer:reindex
php -d memory_limit=-1 bin/magento cache:flush
chown -R "$HOST_USER_ID:$HOST_GROUP_ID" "$APP_DIR"
chgrp -R www-data var generated pub/static pub/media app/etc
chmod -R ug+rwX var generated pub/static pub/media app/etc
chgrp www-data auth.json
chmod 640 auth.json

echo "Magento ${MAGENTO_VERSION} installed successfully at ${MAGENTO_BASE_URL}"
