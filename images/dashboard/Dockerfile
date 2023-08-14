# syntax=docker/dockerfile:1
ARG CONSUL_IMAGE
ARG CONSUL_VERSION
ARG ENVOY_IMAGE
ARG ENVOY_VERSION

FROM ${CONSUL_IMAGE}:${CONSUL_VERSION} as consul-bin
FROM ${ENVOY_IMAGE}:${ENVOY_VERSION} as envoy-bin

FROM alpine:3.18.2 as dashboard-bin
ARG BUILDOS
ARG BUILDARCH
ARG DASHBOARD_VERSION=v0.0.5

ADD https://github.com/hashicorp/demo-consul-101/releases/download/${DASHBOARD_VERSION}/dashboard-service_${BUILDOS}_${BUILDARCH}.zip /dashboard-service.zip
RUN  unzip dashboard-service.zip && mv dashboard-service_${BUILDOS}_${BUILDARCH} dashboard-service


FROM ubuntu:jammy
ENV CONSUL_LICENSE_PATH=/consul/license/consul.hclic

RUN apt-get update \
  && apt-get install -y bash curl dumb-init iproute2 jq openssl \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
  && mkdir -p /consul/data \
  && mkdir -p /consul/config

COPY --from=consul-bin /bin/consul /bin/consul
COPY --from=envoy-bin /usr/local/bin/envoy /bin/envoy
COPY --from=dashboard-bin /dashboard-service /bin/dashboard

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
