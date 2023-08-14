# syntax=docker/dockerfile:1
ARG CONSUL_IMAGE
ARG CONSUL_VERSION
ARG ENVOY_IMAGE
ARG ENVOY_VERSION

FROM ${CONSUL_IMAGE}:${CONSUL_VERSION} as consul-bin
FROM ${ENVOY_IMAGE}:${ENVOY_VERSION} as envoy-bin

FROM alpine:3.18.2 as counting-bin
ARG BUILDOS
ARG BUILDARCH
ARG COUNTING_VERSION=v0.0.5

ADD https://github.com/hashicorp/demo-consul-101/releases/download/${COUNTING_VERSION}/counting-service_${BUILDOS}_${BUILDARCH}.zip /counting-service.zip
RUN  unzip counting-service.zip && mv counting-service_${BUILDOS}_${BUILDARCH} counting-service


FROM ubuntu:jammy
ENV CONSUL_LICENSE_PATH=/consul/license/consul.hclic

RUN apt-get update \
  && apt-get install -y bash curl dumb-init iproute2 iptables jq openssl \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
  && mkdir -p /consul/data \
  && mkdir -p /consul/config

COPY --from=consul-bin /bin/consul /bin/consul
COPY --from=envoy-bin /usr/local/bin/envoy /bin/envoy
COPY --from=counting-bin /counting-service /bin/counting

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
