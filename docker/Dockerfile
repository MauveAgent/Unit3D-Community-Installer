# syntax=docker/dockerfile:1
FROM php:8.4-fpm-bookworm AS php-base
RUN apt-get update && apt-get install -y --no-install-recommends \
    libzip-dev libpng-dev libjpeg62-turbo-dev libfreetype6-dev libicu-dev \
    unzip git gosu default-mysql-client jpegoptim optipng pngquant gifsicle webp \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j2 bcmath gd intl pdo_mysql zip opcache pcntl \
    && pecl install redis-6.2.0 && docker-php-ext-enable redis \
    && rm -rf /var/lib/apt/lists/*
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer
WORKDIR /var/www/html

FROM php-base AS vendor
COPY app/ ./
RUN composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader --no-scripts
# Run package discovery without build secrets or a running database.
RUN mkdir -p storage/framework/cache/data storage/framework/sessions storage/framework/views storage/logs \
    && composer run-script post-autoload-dump

FROM oven/bun:1.3.0 AS assets
WORKDIR /build
COPY app/package.json app/bun.lockb ./
RUN bun install --frozen-lockfile
COPY app/ ./
COPY --from=vendor /var/www/html/vendor ./vendor
ARG APP_URL
ENV VITE_ECHO_ADDRESS=$APP_URL
RUN bun run build

FROM php-base AS app
COPY --from=vendor /var/www/html/ ./
COPY --from=assets /build/public/build ./public/build
COPY docker/php.ini /usr/local/etc/php/conf.d/unit3d.ini
COPY docker/entrypoint.sh /usr/local/bin/unit3d-entrypoint
COPY docker/initialize.sh /usr/local/bin/unit3d-initialize
RUN chmod 755 /usr/local/bin/unit3d-* && rm -f .env \
    && ln -sfn /var/www/html/storage/app/public public/storage
ENTRYPOINT ["unit3d-entrypoint"]
CMD ["php-fpm"]

FROM nginx:1.28-bookworm AS web
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=assets /build/public /var/www/html/public
RUN ln -sfn /var/www/html/storage/app/public /var/www/html/public/storage

FROM node:22-bookworm-slim AS echo
WORKDIR /var/www/html
COPY --from=assets /build/node_modules ./node_modules
USER node
CMD ["node", "node_modules/laravel-echo-server/bin/server.js", "start", "--dir=/var/www/html"]
