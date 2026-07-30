ARG PHP_VERSION=7.4
ARG COMPOSER_VERSION=1
ARG COMPOSER_INSTALL_VERSION=2.0.8

FROM composer:${COMPOSER_VERSION} AS composer_source
FROM composer:${COMPOSER_INSTALL_VERSION} AS composer_install_source

FROM php:${PHP_VERSION}-fpm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        cron \
        curl \
        default-mysql-client \
        git \
        libcurl4-openssl-dev \
        libfreetype6-dev \
        libicu-dev \
        libjpeg62-turbo-dev \
        libonig-dev \
        libpng-dev \
        libsodium-dev \
        libxml2-dev \
        libxslt1-dev \
        libzip-dev \
        unzip \
        zip \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
        bcmath \
        curl \
        gd \
        intl \
        mbstring \
        opcache \
        pdo_mysql \
        soap \
        sockets \
        sodium \
        xsl \
        zip \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer_source /usr/bin/composer /usr/local/bin/composer
COPY --from=composer_install_source /usr/bin/composer /usr/local/bin/composer-install

WORKDIR /var/www/html
