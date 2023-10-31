#!/usr/bin/env bash
set -oeu pipefail

ccvp1_port="$(docker inspect ccvp-1-consul-server-1 | jq -r '.[].NetworkSettings.Ports."8501/tcp" | .[].HostPort')"
export CONSUL_HTTP_SSL_VERIFY=false

# deploy api gateway - creates api-gateway config entry and http-route resources see images/gateway/entrypoint.sh
docker run -d \
  --name ccvp-1-consul-agw \
  --hostname ccvp-1-agw \
  --network ccvp-flat \
  -e COMPOSE_PROJECT_NAME=ccvp-1 \
  -e CONSUL_GOSSIP_KEY="$(awk -F\" '/^CONSUL_GOSSIP_KEY/ {print $(NF -1)}' .env)" \
  -e CONSUL_HTTP_TOKEN="$(awk -F\" '/^CONSUL_TOKEN/ {print $(NF -1)}' .env)" \
  -e GATEWAY_KIND=api \
  -v ccvp-1_consul_pki:/consul/tls:ro \
  -v ./secrets:/consul/license:ro \
  local/consul-gateway:ccvp
agw_addr="$(docker inspect ccvp-1-consul-agw | jq -r '.[].NetworkSettings.Networks."ccvp-flat".IPAddress')"

# deploy external downstream --
docker run -d --rm \
  --name ccvp-1-dashboard-external \
  --hostname ccvp-1-dashboard-external \
  --network ccvp-flat \
  --add-host counting.default.bridge.internal:$agw_addr \
  -p 9998:9998/tcp \
  -e PORT=9998 \
  -e COUNTING_SERVICE_URL="http://counting.default.bridge.internal:8080" \
  hashicorp/dashboard-service:0.0.4

# authorize
consul config write -http-addr="https://localhost:$ccvp1_port" - <<EOF
Kind      = "service-intentions"
Name      = "counting"
Partition = "default"
Namespace = "default"
Sources = [
  {
    Name      = "api-gateway"
    Partition = "default"
    Action    = "allow"
  }
]
EOF
