FROM debian:bookworm-slim

ARG API_REPOSITORY="https://github.com/cipherguard/cipherguard_api"
ARG IMAGE_DESCRIPTION="Cipherguard CE Backend, a JSON API written with CakePHP"
ARG BUILD_DATE=""

LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.description="${IMAGE_DESCRIPTION}"
LABEL org.opencontainers.image.documentation=https://help.cipherguard.com/
LABEL org.opencontainers.image.authors="Cipherguard SA <contact@cipherguard.com>"
LABEL org.opencontainers.image.licenses=AGPL-3.0-only
LABEL org.opencontainers.image.source="${API_REPOSITORY}"
LABEL org.opencontainers.image.title=cipherguard/cipherguard
LABEL org.opencontainers.image.url=https://cipherguard.com

ARG CIPHERGUARD_DISTRO="buster"
ARG CIPHERGUARD_COMPONENT="stable"
ARG CIPHERGUARD_FLAVOUR="ce"
ARG CIPHERGUARD_SERVER_KEY="https://download.cipherguard.com"
ARG CIPHERGUARD_REPO_URL="https://download.cipherguard.com"
ARG CIPHERGUARD_REPO_KEY_PATH="/usr/share/keyrings/cipherguard-repository.gpg"
ARG CIPHERGUARD_SOURCES_LIST_PATH="/etc/apt/sources.list.d/cipherguard.sources"

ENV CIPHERGUARD_PKG_KEY=0xDE8B853FC155581D
ENV PHP_VERSION=8.2
ENV GNUPGHOME=/var/lib/cipherguard/.gnupg
ENV CIPHERGUARD_FLAVOUR=$CIPHERGUARD_FLAVOUR
ENV CIPHERGUARD_PKG="cipherguard-$CIPHERGUARD_FLAVOUR-server"
ENV LOG_ERROR_URL="console://?levels[]=warning&levels[]=error&levels[]=critical&levels[]=alert&levels[]=emergency"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update \
  && DEBIAN_FRONTEND=non-interactive apt-get -y install \
  ca-certificates \
  gnupg \
  curl \
  && curl -s $CIPHERGUARD_SERVER_KEY/pub.key |\
  gpg --dearmor | tee $CIPHERGUARD_REPO_KEY_PATH > /dev/null \
  && chmod 644 $CIPHERGUARD_REPO_KEY_PATH \
  && echo -e "Types: deb \nURIs: $CIPHERGUARD_REPO_URL/$CIPHERGUARD_FLAVOUR/debian \nSuites: $CIPHERGUARD_DISTRO \nComponents: $CIPHERGUARD_COMPONENT \nSigned-By: $CIPHERGUARD_REPO_KEY_PATH" > $CIPHERGUARD_SOURCES_LIST_PATH \
  && apt-get update \
  && DEBIAN_FRONTEND=non-interactive apt-get -y install --no-install-recommends \
  nginx \
  $CIPHERGUARD_PKG \
  supervisor \
  && rm -f /etc/cipherguard/jwt/* \
  && rm /etc/nginx/sites-enabled/default \
  && cp /usr/share/cipherguard/examples/nginx-cipherguard-ssl.conf /etc/nginx/snippets/cipherguard-ssl.conf \
  && sed -i 's,;clear_env = no,clear_env = no,' /etc/php/$PHP_VERSION/fpm/pool.d/www.conf \
  && sed -i 's,# include __CIPHERGUARD_SSL__,include /etc/nginx/snippets/cipherguard-ssl.conf;,' /etc/nginx/sites-enabled/nginx-cipherguard.conf \
  && sed -i '/listen \[\:\:\]\:443 ssl http2;/a listen 443 ssl http2;' /etc/nginx/snippets/cipherguard-ssl.conf \
  && sed -i 's,__CERT_PATH__,/etc/ssl/certs/certificate.crt;,' /etc/nginx/snippets/cipherguard-ssl.conf \
  && sed -i 's,__KEY_PATH__,/etc/ssl/certs/certificate.key;,' /etc/nginx/snippets/cipherguard-ssl.conf \
  && sed -i 's,www-data.*$,root su -s /bin/bash -c ". /etc/environment \&\& $CIPHERGUARD_BASE_DIR/bin/cron" www-data >/proc/1/fd/1 2>\&1,' /etc/cron.d/$CIPHERGUARD_PKG \
  && sed -i 's/# server_tokens/server_tokens/' /etc/nginx/nginx.conf \
  && ln -sf /dev/stdout /var/log/nginx/cipherguard-access.log \
  && ln -sf /dev/stderr /var/log/nginx/cipherguard-error.log

COPY conf/supervisor/cron.conf /etc/supervisor/conf.d/cron.conf
COPY conf/supervisor/nginx.conf /etc/supervisor/conf.d/nginx.conf
COPY conf/supervisor/php.conf /etc/supervisor/conf.d/php.conf
COPY conf/php/zz-docker.conf /etc/php/$PHP_VERSION/fpm/pool.d/zz-docker.conf

COPY scripts/entrypoint/docker-entrypoint.sh /docker-entrypoint.sh
COPY scripts/entrypoint/cipherguard/entrypoint.sh /cipherguard/entrypoint.sh
COPY scripts/entrypoint/cipherguard/env.sh /cipherguard/env.sh
COPY scripts/entrypoint/cipherguard/deprecated_paths.sh /cipherguard/deprecated_paths.sh
COPY scripts/entrypoint/cipherguard/entropy.sh /cipherguard/entropy.sh
COPY scripts/wait-for.sh /usr/bin/wait-for.sh

RUN chmod 0644 /etc/supervisor/conf.d/* \
  && chmod 0700 /docker-entrypoint.sh \
  && chmod 0700 /cipherguard/* \
  && chmod 0700 /usr/bin/wait-for.sh

EXPOSE 80 443

WORKDIR /usr/share/php/cipherguard

CMD ["/docker-entrypoint.sh"]
