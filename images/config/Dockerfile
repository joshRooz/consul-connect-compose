# syntax=docker/dockerfile:1
ARG CONSUL_IMAGE
ARG CONSUL_VERSION
ARG VAULT_IMAGE
ARG VAULT_VERSION

FROM ${CONSUL_IMAGE}:${CONSUL_VERSION} as consul-bin
FROM ${VAULT_IMAGE}:${VAULT_VERSION} as vault-bin

FROM alpine:3.18.2
ENV CONSUL_LICENSE_PATH=/consul/license/consul.hclic
ENV VAULT_LICENSE_PATH=/vault/license/vault.hclic

RUN apk update \
  && apk add --no-cache bash curl jq openssl \
  && rm -rf /var/cache/apk/* /tmp/* /var/tmp/*

COPY --from=consul-bin /bin/consul /bin/consul
COPY --from=vault-bin /bin/vault /bin/vault

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
