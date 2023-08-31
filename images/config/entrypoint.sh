#!/bin/bash
set -eou pipefail

#env | grep -e CONSUL -e COMPOSE_PROJECT_NAME

# generate consul agent ca and leaf cert for the server instance
if [ ! -s "${COMPOSE_PROJECT_NAME}-server-consul-0.pem" ]  ; then
  cd /consul-pki
  consul tls ca create
  consul tls cert create -server -dc="${COMPOSE_PROJECT_NAME}" -additional-dnsname="${COMPOSE_PROJECT_NAME}-consul-server"
  chown 100:1000 "${COMPOSE_PROJECT_NAME}-server-consul-0.pem" "${COMPOSE_PROJECT_NAME}-server-consul-0-key.pem"
fi

# apply config to consul once leader is established
cnt=1
until curl --fail --silent --insecure "${CONSUL_HTTP_ADDR}/v1/status/leader" | grep -q :8300
do
  sleep $((cnt *= 2 ))
done

curl --insecure --fail-with-body \
--header "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
--request PUT "${CONSUL_HTTP_ADDR}/v1/config" \
--data @- <<EOF
{
  "kind": "proxy-defaults",
  "name": "global",
  "namespace": "default",
  "access_logs": {
    "enabled": true
  },
  "config": {
    "protocol": "http",
    "envoy_prometheus_bind_addr": "0.0.0.0:19001",
    "envoy_stats_bind_addr": "0.0.0.0:19002"
  },
  "mesh_gateway": {
    "mode": "local"
  }
}
EOF

until curl --fail --silent "${CONSUL_HTTP_ADDR}/v1/connect/ca/roots" | tee /consul-pki/connect-ca.pem ; do
  sleep 2
done


exit 0
