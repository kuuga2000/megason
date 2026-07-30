# Magento 2.3.7-p4 Docker requirements

The host needs only Docker with Docker Compose v2 support. On Windows with WSL 2,
enable Docker Desktop integration for the Linux distribution. Do not install PHP,
Composer, MariaDB, Elasticsearch, Redis, RabbitMQ, Varnish, or Nginx on Ubuntu.

All application requirements are provided by containers:

- Magento Open Source 2.3.7-p4 (installed in a later step)
- PHP-FPM 7.4 with Magento-required PHP extensions
- Composer 1
- MariaDB 10.3
- Elasticsearch 7.16.3 (the final 7.16 patch release)
- Redis 6.0
- RabbitMQ 3.8 with the management UI
- Varnish 6.5
- Nginx 1.18

## Host ports

These ports deliberately avoid the ports published by the sibling `megaton`
project:

| Service | Host | Container |
|---|---:|---:|
| Nginx | 8082 | 80 |
| Varnish | 8083 | 80 |
| MariaDB | 3308 | 3306 |
| Elasticsearch | 9201 | 9200 |
| Redis | 6380 | 6379 |
| RabbitMQ AMQP | 5673 | 5672 |
| RabbitMQ management | 15673 | 15672 |

PHP-FPM is available only inside the Docker network on port 9000.
