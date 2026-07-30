# Megason — Magento 2.3.7-p4 Docker Environment

Megason is a local study environment for Magento Open Source `2.3.7-p4`.
Magento and every supporting service run in Docker; PHP, Composer, databases,
search engines, queues, caches, Varnish, and Nginx do not need to be installed
directly on Ubuntu or WSL.

Apache and MySQL are not used. Nginx and MariaDB are used instead.

## Stack

| Component | Version |
|---|---:|
| Magento Open Source | 2.3.7-p4 |
| PHP-FPM | 7.4 |
| Composer | 1 |
| MariaDB | 10.3 |
| Elasticsearch | 7.16.3 |
| Redis | 6.0 |
| RabbitMQ | 3.8 |
| Varnish | 6.5 |
| Nginx | 1.18 |

Magento source is stored in `magento237/` and mounted into the PHP-FPM and
Nginx containers at `/var/www/html`.

## Local URLs

| Service | URL |
|---|---|
| Storefront through Nginx | <http://localhost:8082/> |
| Magento Admin | <http://localhost:8082/admin> |
| Storefront through Varnish | <http://localhost:8083/> |
| RabbitMQ management | <http://localhost:15673/> |
| Elasticsearch | <http://localhost:9201/> |

Additional published ports:

| Service | Host port | Container port |
|---|---:|---:|
| MariaDB | 3308 | 3306 |
| Redis | 6380 | 6379 |
| RabbitMQ AMQP | 5673 | 5672 |

These host ports intentionally avoid conflicts with the sibling `megaton`
project.

## Study Credentials and `.env`

The usernames and passwords in this project are intentionally simple and
exposed for study in a local-only Docker environment. They make it easier to
understand how Magento connects to MariaDB, RabbitMQ, Redis, Elasticsearch, and
the other containers.

They are **not suitable for production, staging, a public server, or any
internet-accessible environment**. Before using this project outside an
isolated local machine, replace every database, RabbitMQ, and Magento Admin
credential with strong unique secrets.

The real `.env` remains excluded by `.gitignore` because it may contain Magento
Marketplace public/private access keys. Do not commit or publish:

- `MAGENTO_PUBLIC_KEY`
- `MAGENTO_PRIVATE_KEY`
- `magento237/auth.json`

The ordinary study credentials may be documented, but Marketplace credentials
must always remain private. If an access key has ever been committed, revoke it
in Adobe Commerce Marketplace and create a replacement.

## Requirements

The host requires only:

- Docker
- Docker Compose v2
- WSL 2 integration when running through Docker Desktop on Windows

Do not install Magento requirements directly on Ubuntu. See
[REQUIREMENTS.md](REQUIREMENTS.md) for the complete version and port matrix.

## Start the Environment

From the project directory:

```sh
docker compose up -d
docker compose ps
```

To build the images again:

```sh
docker compose up -d --build
```

## Install Magento

Add valid Magento Marketplace keys to the local `.env`, then run:

```sh
./magento237/install.sh
```

The installer:

1. Downloads Magento Open Source `2.3.7-p4` inside Docker.
2. Installs Magento with MariaDB, Elasticsearch, Redis, and RabbitMQ.
3. Deploys the Luma and Admin static assets.
4. Normalizes Magento 2.3 icon-font CSS escapes.
5. Rebuilds indexes and flushes caches.
6. Restores host ownership while retaining PHP-FPM write access to runtime
   directories.

The ownership handoff uses the UID and GID of the user invoking `install.sh`.
This prevents container-created root-owned source files from blocking Git
branch checkouts.

## Official Luma Sample Data

This environment includes Magento's official sample data, providing demo
products, categories, images, CMS pages, blocks, widgets, reviews, and
promotions.

If installing it in a fresh database, follow the documented commands in
[BOOK.md](BOOK.md). Magento `2.3.7-p4` uses the `100.3.*` sample-data package
line.

## Useful Commands

Check services:

```sh
docker compose ps
```

Run Magento CLI:

```sh
docker compose exec phpfpm \
  php -d memory_limit=-1 bin/magento list
```

Flush Magento caches:

```sh
docker compose exec phpfpm \
  php -d memory_limit=-1 bin/magento cache:flush
```

Reindex:

```sh
docker compose exec phpfpm \
  php -d memory_limit=-1 bin/magento indexer:reindex
```

Redeploy static content:

```sh
docker compose exec phpfpm \
  php -d memory_limit=-1 bin/magento setup:static-content:deploy -f en_US
docker compose exec phpfpm ./fix-static-icon-escapes.sh
docker compose exec phpfpm \
  php -d memory_limit=-1 bin/magento cache:flush
docker compose restart varnish
```

Stop the environment:

```sh
docker compose stop
```

Remove containers and the Docker network while preserving data volumes:

```sh
docker compose down
```

Do not add `-v` unless the MariaDB, Elasticsearch, Redis, and RabbitMQ volumes
should be deleted intentionally.

## Git and File Ownership

Magento runtime directories must be writable by PHP-FPM, while source files
should remain owned by the host user. The intended arrangement is:

- Magento source: host user and host group
- `var`, `generated`, `pub/static`, `pub/media`, and `app/etc`: writable by
  owner and the container `www-data` group
- `auth.json`: mode `640`, readable by `www-data`

Avoid running host-side `sudo composer`, `sudo git`, or other commands inside
`magento237/`. Use the provided Docker commands instead.

## Documentation

[BOOK.md](BOOK.md) contains the complete chronological build, installation,
troubleshooting, sample-data, Varnish, static-content, CORS, and permission
notes for this environment.
