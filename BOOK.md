# Megason Build Notes

This book records the successful Docker-only build of Magento Open Source
`2.3.7-p4`. It includes the final architecture, exact commands, problems found,
and the fixes needed to run this 2021 Magento release on Docker Desktop in 2026.

## Goal

Build and install Magento Open Source `2.3.7-p4` without installing PHP,
Composer, MariaDB, Elasticsearch, Redis, RabbitMQ, Varnish, or Nginx directly
on Ubuntu.

The required versions are:

- Magento Open Source `2.3.7-p4`
- PHP-FPM `7.4`
- Composer `1`
- MariaDB `10.3`
- Elasticsearch `7.16`
- Redis `6.0`
- RabbitMQ `3.8`
- Varnish `6.5`
- Nginx `1.18`

Apache is not used. MariaDB is used instead of MySQL.

## Project Structure

The project was created at:

```text
/home/guosong/dev/megason
```

Magento source is stored at:

```text
/home/guosong/dev/megason/magento237
```

Final top-level structure:

```text
megason/
├── .env
├── .gitignore
├── BOOK.md
├── REQUIREMENTS.md
├── docker-compose.yml
├── elasticsearch/
│   └── Dockerfile
├── magento237/
│   ├── Dockerfile
│   ├── install.sh
│   ├── install-magento.sh
│   └── Magento source files
├── mariadb/
│   └── Dockerfile
├── nginx/
│   ├── Dockerfile
│   └── default.conf
├── rabbitmq/
│   └── Dockerfile
├── redis/
│   └── Dockerfile
└── varnish/
    ├── Dockerfile
    └── default.vcl
```

## Step 1: Create the Initial Structure

The directories were created with:

```sh
cd /home/guosong/dev

mkdir -p \
  megason/magento237 \
  megason/mariadb \
  megason/elasticsearch \
  megason/redis \
  megason/rabbitmq \
  megason/varnish \
  megason/nginx

touch megason/.env megason/.gitignore
```

The initial `.gitignore` excludes local secrets, Magento dependencies, generated
files, caches, media, static files, and editor noise. In particular, these files
must not be committed:

```text
.env
magento237/auth.json
magento237/app/etc/env.php
```

The `.env` contains version pins, internal service hosts and ports, host port
mappings, database credentials, RabbitMQ credentials, admin credentials, and
Magento Marketplace key variables.

Never print or commit these Marketplace values:

```text
MAGENTO_PUBLIC_KEY
MAGENTO_PRIVATE_KEY
```

## Step 2: Avoid Megaton Port Conflicts

The sibling `megaton` project already publishes several ports. `megason` uses a
separate host port set:

| Service | Host port | Container port |
|---|---:|---:|
| Nginx | `8082` | `80` |
| Varnish | `8083` | `80` |
| MariaDB | `3308` | `3306` |
| Elasticsearch | `9201` | `9200` |
| Redis | `6380` | `6379` |
| RabbitMQ AMQP | `5673` | `5672` |
| RabbitMQ management | `15673` | `15672` |
| PHP-FPM | not published | `9000` |

Containers communicate through the `megason` Docker network with service names,
not host ports. For example, Magento connects to `mariadb:3306`,
`elasticsearch:9200`, `redis:6379`, and `rabbitmq:5672`.

## Step 3: Build the Docker Requirements

The Compose configuration defines seven services:

- `phpfpm`
- `nginx`
- `mariadb`
- `elasticsearch`
- `redis`
- `rabbitmq`
- `varnish`

Named volumes persist MariaDB, Elasticsearch, Redis, and RabbitMQ data.

Docker availability and Compose syntax were checked with:

```sh
cd /home/guosong/dev/megason
docker --version
docker compose version
docker compose config --quiet
```

The images were built with:

```sh
docker compose build
```

The stack was started with:

```sh
docker compose up -d
```

The initial PHP-FPM image includes Magento's required PHP extensions:

```text
bcmath
curl
gd
intl
mbstring
opcache
pdo_mysql
soap
sockets
sodium
xsl
zip
```

It also contains only in the container:

```text
curl
git
cron
unzip
zip
MariaDB client tools
```

No package was installed directly on Ubuntu.

## Important Docker Build Fixes

### BuildKit Composer Stage

The first PHP Dockerfile tried to use a variable directly in `COPY --from`:

```Dockerfile
COPY --from=composer:${COMPOSER_VERSION} ...
```

Modern BuildKit rejected it:

```text
variable expansion is not supported for --from
```

The fix was to create a named Composer stage:

```Dockerfile
ARG COMPOSER_VERSION=1
FROM composer:${COMPOSER_VERSION} AS composer_source

FROM php:7.4-fpm
COPY --from=composer_source /usr/bin/composer /usr/local/bin/composer
```

### Elasticsearch 7.16.3 and Modern Docker Desktop

Elasticsearch `7.16.3` initially exited with a cgroup-v2 error from its bundled
early Java 17 runtime:

```text
java.lang.NullPointerException:
Cannot invoke "jdk.internal.platform.CgroupInfo.getMountPoint()"
because "anyController" is null
```

Two attempted JVM flag workarounds were insufficient because Elasticsearch's
entrypoint ignored `JAVA_TOOL_OPTIONS`, and the JVM-options parser crashed before
reading `ES_JAVA_OPTS`.

The durable fix was to keep Elasticsearch exactly at `7.16.3` but replace only
its bundled JDK with a current Java 17 runtime in a multi-stage image:

```Dockerfile
FROM eclipse-temurin:17-jre AS current_jre
FROM docker.elastic.co/elasticsearch/elasticsearch:7.16.3

USER root
RUN rm -rf /usr/share/elasticsearch/jdk
COPY --from=current_jre --chown=elasticsearch:root \
    /opt/java/openjdk /usr/share/elasticsearch/jdk
USER elasticsearch
```

After rebuilding Elasticsearch, it became healthy:

```sh
docker compose build elasticsearch
docker compose up -d
```

The verified result was:

```text
Elasticsearch 7.16.3
JVM 17.0.19
```

## Step 4: Verify All Requirement Containers

The final versions were checked inside Docker:

```sh
docker compose exec -T phpfpm php -v
docker compose exec -T phpfpm composer --version
docker compose exec -T mariadb mysql --version
docker compose exec -T elasticsearch /usr/share/elasticsearch/bin/elasticsearch --version
docker compose exec -T redis redis-server --version
docker compose exec -T rabbitmq rabbitmqctl version
docker compose exec -T varnish varnishd -V
docker compose exec -T nginx nginx -v
```

Verified versions:

```text
PHP: 7.4.33
Composer: 1.10.28
MariaDB: 10.3.39
Elasticsearch: 7.16.3
Redis: 6.0.20
RabbitMQ: 3.8.34
Varnish: 6.5.1
Nginx: 1.18.0
```

Connectivity checks included:

```sh
curl -fsS http://localhost:9201/
docker compose exec -T redis redis-cli ping
docker compose exec -T mariadb mysql \
  -umagento237 -pmagento237 \
  -e 'SELECT DATABASE(), VERSION();' magento237
curl -fsS -u magento237:magento237 \
  http://localhost:15673/api/overview
```

Expected results include:

```text
Redis: PONG
MariaDB database: magento237
Elasticsearch version: 7.16.3
RabbitMQ management API: HTTP success
```

## Step 5: Create the Magento Installer Scripts

Two scripts similar to the `megaton` project were created:

```text
magento237/install.sh
magento237/install-magento.sh
```

`install.sh` runs the actual installer inside PHP-FPM:

```sh
docker compose run --rm phpfpm sh /var/www/html/install-magento.sh
```

After installation, it ensures PHP-FPM, Nginx, and Varnish are running.

`install-magento.sh` performs these actions:

1. Loads service and admin settings from container environment variables.
2. Creates `auth.json` from the Marketplace keys when needed.
3. Downloads exactly Magento Open Source `2.3.7-p4`.
4. Waits for MariaDB and Elasticsearch.
5. Detects complete versus incomplete database installation.
6. Runs `setup:install` with MariaDB, RabbitMQ, and Redis settings.
7. Configures Elasticsearch 7 using Magento 2.3-compatible commands.
8. Enables developer mode.
9. Deploys `en_US` storefront and admin static assets.
10. Reindexes all Magento indexes.
11. Flushes caches and fixes runtime permissions.

Run it with:

```sh
cd /home/guosong/dev/megason
./magento237/install.sh
```

## Composer 1 Shutdown Compatibility

Magento authenticated and the root package downloaded with Composer 1, but
dependency resolution failed because Packagist ended Composer 1 metadata support
on September 1, 2025. Composer reported many packages as unavailable, including:

```text
braintree/braintree_php
phpunit/phpunit
friendsofphp/php-cs-fixer
magento/magento-coding-standard
```

The Magento root-update plugin introduced a second constraint: it accepts only
early Composer 2 releases. Composer `2.0.8` was selected because every eligible
`1.1.x` release of the plugin accepts it, making it a safe bootstrap version for
this legacy project.

The final image therefore provides:

```text
composer          -> Composer 1.10.28, the requested normal runtime
composer-install  -> Composer 2.0.8, installation bootstrap only
```

Composer 1 remains the default environment requirement. Composer 2.0.8 is used
only inside `install-magento.sh` to access modern Packagist metadata while
remaining compatible with Magento `2.3.7-p4`.

The legacy dependency graph also exceeded Composer's default 1.5 GB memory
limit. The bootstrap command was changed to:

```sh
COMPOSER_MEMORY_LIMIT=-1 composer-install create-project \
  --repository-url=https://repo.magento.com/ \
  magento/project-community-edition=2.3.7-p4 \
  /tmp/magento237
```

This resolved and installed 475 packages successfully.

## Magento 2.3 Search Configuration Difference

The first `setup:install` command used later Magento CLI options:

```text
--search-engine
--elasticsearch-host
--elasticsearch-port
```

Magento `2.3.7-p4` rejected them:

```text
The "--search-engine" option does not exist.
```

The fix was to run `setup:install` without those options and configure search
immediately afterward with Magento 2.3 configuration paths:

```sh
php bin/magento config:set catalog/search/engine elasticsearch7
php bin/magento config:set \
  catalog/search/elasticsearch7_server_hostname elasticsearch
php bin/magento config:set \
  catalog/search/elasticsearch7_server_port 9200
php bin/magento config:set \
  catalog/search/elasticsearch7_index_prefix magento237
php bin/magento config:set \
  catalog/search/elasticsearch7_enable_auth 0
```

## Magento CLI Memory Fix

The first database installation reached step `558 / 1005`, then Magento's own
composer-root-update data patch exhausted the PHP CLI default of 128 MB:

```text
Fatal error: Allowed memory size of 134217728 bytes exhausted
```

All Magento installation and maintenance commands in the script were changed to:

```sh
php -d memory_limit=-1 bin/magento ...
```

Because the failed attempt left a partial schema, the installer was made
idempotent:

- If `app/etc/env.php` exists and `setup:db:status` succeeds, installation exits
  safely.
- If deployment configuration exists but database status is incomplete, setup is
  restarted with Magento's `--cleanup-database` option.

The clean retry completed all `1006 / 1006` steps:

```text
[SUCCESS]: Magento installation complete.
[SUCCESS]: Magento Admin URI: /admin
```

## Magento Runtime Permission Fix

After successful installation, the storefront and admin initially returned HTTP
500. Magento's log showed:

```text
Can't create directory /var/www/html/generated/code/...
the 'generated' directory permission is read-only
```

Changing ownership alone was insufficient because Magento's post-install
security step removed write mode bits. The fix was:

```sh
docker compose exec -T -u root phpfpm \
  chown -R www-data:www-data var generated pub/static pub/media app/etc

docker compose exec -T -u root phpfpm \
  chmod -R ug+rwX var generated pub/static pub/media app/etc

docker compose exec -T phpfpm \
  php -d memory_limit=-1 bin/magento cache:flush
```

The same ownership and mode correction is now part of the installer script.

After this fix:

```text
Storefront: HTTP 200
Admin: HTTP 302 redirect to login
Varnish: HTTP 200
```

## Initial Reindex

The installation completed with several indexes marked `Reindex required`.
They were rebuilt with:

```sh
docker compose exec -T phpfpm \
  php -d memory_limit=-1 bin/magento indexer:reindex
```

Status was verified with:

```sh
docker compose exec -T phpfpm php bin/magento indexer:status
```

All indexes reported `Ready`, including Catalog Search. This also verified that
Magento could connect to Elasticsearch 7.16.3.

## Final Magento Verification

Magento version:

```sh
docker compose exec -T phpfpm \
  php -d memory_limit=-1 bin/magento --version
```

Result:

```text
Magento CLI 2.3.7-p4
```

Database status:

```sh
docker compose exec -T phpfpm \
  php -d memory_limit=-1 bin/magento setup:db:status
```

Result:

```text
All modules are up to date.
```

Search configuration:

```sh
docker compose exec -T phpfpm \
  php bin/magento config:show catalog/search/engine
docker compose exec -T phpfpm \
  php bin/magento config:show catalog/search/elasticsearch7_server_hostname
docker compose exec -T phpfpm \
  php bin/magento config:show catalog/search/elasticsearch7_server_port
```

Result:

```text
elasticsearch7
elasticsearch
9200
```

HTTP checks:

```sh
curl -sS -o /dev/null -w '%{http_code}\n' http://localhost:8082/
curl -sS -o /dev/null -w '%{http_code}\n' http://localhost:8082/admin
curl -sS -o /dev/null -w '%{http_code}\n' http://localhost:8083/
```

Expected results:

```text
Storefront: 200
Admin: 302
Varnish: 200
```

## Final URLs and Credentials

Storefront:

```text
http://localhost:8082/
```

Admin:

```text
http://localhost:8082/admin
```

Admin credentials:

```text
Username: admin
Password: Admin123!Admin123!
Email: admin@example.com
```

Varnish frontend:

```text
http://localhost:8083/
```

RabbitMQ management:

```text
URL: http://localhost:15673/
Username: magento237
Password: magento237
```

MariaDB host access:

```text
Host: localhost
Port: 3308
Database: magento237
Username: magento237
Password: magento237
Root password: root
```

## Daily Commands

Start the environment:

```sh
cd /home/guosong/dev/megason
docker compose up -d
```

Show status:

```sh
docker compose ps
```

Follow logs:

```sh
docker compose logs -f
```

Run Magento CLI:

```sh
docker compose exec phpfpm php -d memory_limit=-1 bin/magento list
```

Flush cache:

```sh
docker compose exec phpfpm \
  php -d memory_limit=-1 bin/magento cache:flush
```

Reindex:

```sh
docker compose exec phpfpm \
  php -d memory_limit=-1 bin/magento indexer:reindex
```

Stop containers without deleting them:

```sh
docker compose stop
```

Start stopped containers:

```sh
docker compose start
```

Remove containers and the network while preserving named volumes:

```sh
docker compose down
```

Do not add `-v` unless database, Elasticsearch, Redis, and RabbitMQ data should
be deleted intentionally.

## After Magento Code Changes

Magento source on the host:

```text
/home/guosong/dev/megason/magento237
```

The same directory inside PHP-FPM and Nginx:

```text
/var/www/html
```

After ordinary configuration or template changes:

```sh
docker compose exec phpfpm \
  php -d memory_limit=-1 bin/magento cache:flush
```

After module, schema, dependency-injection, plugin, preference, observer, or
constructor changes:

```sh
docker compose exec phpfpm \
  php -d memory_limit=-1 bin/magento setup:upgrade
docker compose exec phpfpm \
  php -d memory_limit=-1 bin/magento setup:di:compile
docker compose exec phpfpm \
  php -d memory_limit=-1 bin/magento cache:flush
```

For static asset problems:

```sh
docker compose exec phpfpm \
  php -d memory_limit=-1 bin/magento setup:static-content:deploy -f en_US
docker compose exec phpfpm \
  php -d memory_limit=-1 bin/magento cache:flush
```

## Fixing a Storefront or Admin Page with Broken Styling

After the first installation, the storefront HTML loaded but the page appeared
unstyled. Browser requests for Luma CSS, JavaScript, fonts, the logo, and admin
assets returned `404`. The cause was that Magento static content had not yet
been fully deployed: `pub/static` contained only the generated RequireJS
configuration.

Deploy the frontend and admin assets inside the PHP-FPM container, restore the
shared-volume ownership and permissions, and flush Magento caches:

```sh
docker compose exec phpfpm \
  php -d memory_limit=-1 bin/magento setup:static-content:deploy -f en_US
docker compose exec --user root phpfpm \
  chown -R www-data:www-data var generated pub/static pub/media app/etc
docker compose exec --user root phpfpm \
  chmod -R ug+rwX var generated pub/static pub/media app/etc
docker compose exec phpfpm \
  php -d memory_limit=-1 bin/magento cache:flush
```

This deployment is also included in `magento237/install-magento.sh`, so a new
installation creates the Blank, Luma, and Admin theme assets automatically.
The repaired storefront and Varnish routes returned HTTP `200`, `/admin`
returned its expected HTTP `302` login redirect, and the versioned Luma
stylesheet returned `200 text/css` through both Nginx and Varnish.

### Fixing Broken Luma Icon Glyphs

After sample data was installed, rating stars appeared as fragments such as
`e605`. The Luma WOFF and WOFF2 files were present, valid, and returned HTTP
`200` with the correct MIME types. The actual problem was in generated CSS:
Magento 2.3's legacy LESS compiler preserved two backslashes in private-use
icon values. CSS interpreted them as visible text instead of Luma font glyphs.
This could affect ratings, search, cart, navigation arrows, and other icons.

The project includes `magento237/fix-static-icon-escapes.sh`, which normalizes
all deployed frontend and admin CSS icon escapes. Run it immediately after
every static-content deployment:

```sh
docker compose exec phpfpm \
  php -d memory_limit=-1 bin/magento setup:static-content:deploy -f en_US
docker compose exec phpfpm ./fix-static-icon-escapes.sh
docker compose exec phpfpm \
  php -d memory_limit=-1 bin/magento cache:flush
docker compose restart varnish
```

`install-magento.sh` now runs the normalization automatically. A fresh static
deployment also changes Magento's signed asset URL, preventing browsers from
reusing the previously broken long-lived CSS response. Verification confirmed
one backslash byte per `e605` star value, zero double-escaped declarations, and
HTTP `200` through Varnish.

The Varnish URL exposed one additional browser-specific issue. Magento's base
URL is Nginx on port `8082`, so HTML opened through Varnish on port `8083`
contains absolute static URLs pointing to `8082`. Although CSS may load across
those origins, browsers block its web fonts unless the font response permits
cross-origin use. A successful HTTP `200` for the WOFF2 file alone is therefore
not sufficient.

`nginx/default.conf` now adds this response header to Magento static assets:

```nginx
add_header Access-Control-Allow-Origin "*" always;
```

After validating and restarting Nginx, static content was deployed again to
issue a new signed URL, the icon normalization was reapplied, and Varnish was
restarted. The new Luma font response was verified as HTTP `200`, MIME type
`font/woff2`, with `Access-Control-Allow-Origin: *`. This prevents the browser
from rejecting the icon font on the Varnish storefront.

### Fixing Admin `Could not read auth.json`

After logging in to Admin, Magento's admin-notification observer requested the
installed product version through Composer. PHP-FPM runs as `www-data`, but the
root Composer authentication file was owned by `root:root` with mode `600`.
Composer therefore raised `Could not read /var/www/html/auth.json` even though
the storefront itself continued to work.

Keep the Marketplace credentials unavailable to other users while allowing
PHP-FPM to read them:

```sh
docker compose exec --user root phpfpm \
  chown 1000:www-data /var/www/html/auth.json
docker compose exec --user root phpfpm \
  chmod 640 /var/www/html/auth.json
docker compose exec phpfpm \
  php -d memory_limit=-1 bin/magento cache:flush
```

`install-magento.sh` now applies group `www-data` and mode `640` whenever it
creates or reuses `auth.json`. Verification ran Magento's ProductMetadata lookup
as `www-data`, returned `Magento 2.3.7-p4`, and the Admin route resumed its
normal redirect without an `auth.json` permission exception.

## Installing Official Luma Sample Data

The initial Magento installation intentionally contained no demo catalog, so
the Luma homepage displayed only `CMS homepage content goes here.` Official
Magento sample data was then installed into `magento237`.

Magento 2.3.7-p4's CLI normally invokes Composer during sample-data deployment.
Because Composer 1 can no longer retrieve current repository metadata, first
add the matching package constraints without updating, then use the
containerized compatibility Composer to download them:

```sh
docker compose exec phpfpm \
  php -d memory_limit=-1 bin/magento sampledata:deploy \
  --no-update --no-interaction
docker compose exec phpfpm sh -lc \
  'COMPOSER_MEMORY_LIMIT=-1 composer-install update \
  --with-dependencies --no-interaction --prefer-dist'
```

Enable maintenance mode while Magento enables the new modules and imports the
fixtures:

```sh
docker compose exec phpfpm \
  php -d memory_limit=-1 bin/magento maintenance:enable
docker compose exec phpfpm \
  php -d memory_limit=-1 bin/magento setup:upgrade --keep-generated
```

Finish the installation by deploying static content, rebuilding indexes,
restoring shared-volume permissions, flushing caches, and reopening the store:

```sh
docker compose exec phpfpm \
  php -d memory_limit=-1 bin/magento setup:static-content:deploy -f en_US
docker compose exec phpfpm \
  php -d memory_limit=-1 bin/magento indexer:reindex
docker compose exec --user root phpfpm \
  chown -R www-data:www-data var generated pub/static pub/media app/etc
docker compose exec --user root phpfpm \
  chmod -R ug+rwX var generated pub/static pub/media app/etc
docker compose exec phpfpm \
  php -d memory_limit=-1 bin/magento cache:flush
docker compose exec phpfpm \
  php -d memory_limit=-1 bin/magento maintenance:disable
docker compose restart varnish
```

The installed official packages use the Magento 2.3 sample-data release line
`100.3.*`; for example, `Magento_CatalogSampleData` resolved to `100.3.5`.
Verification found 2,040 products, 40 categories, and 18 CMS blocks. The
Catalog, CMS, and Theme sample-data modules were enabled, all indexes reported
`Ready`, demo navigation appeared, and Nginx and Varnish both returned HTTP
`200`.

## Final Result

The final system runs Magento Open Source `2.3.7-p4` entirely in Docker with:

- Nginx serving Magento; no Apache
- MariaDB 10.3; no MySQL service
- Elasticsearch 7.16.3
- Redis 6.0 for cache, page cache, and sessions
- RabbitMQ 3.8 for AMQP
- Varnish 6.5 in front of Nginx
- PHP-FPM 7.4 with Composer 1 as the default Composer command
- Official Luma sample products, categories, CMS content, widgets, and media
- No Magento requirement installed directly on Ubuntu

The installation, database schema, Elasticsearch indexing, storefront, admin
route, static assets, Varnish route, and all Docker services were verified
successfully.
