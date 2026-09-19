ARG VERSION=18
ARG REGISTRY=docker.io/library
FROM $REGISTRY/postgres:$VERSION-alpine

ENV PGDATA=/tmp/data
ENV LANG=C.UTF-8

RUN rm -rf /var/run/postgresql && \
    mkdir -p /var/run/postgresql && \
    chgrp -R 0 /tmp /var/run/postgresql && \
    chmod -R g+rwX /tmp /var/run/postgresql

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

USER 1031
