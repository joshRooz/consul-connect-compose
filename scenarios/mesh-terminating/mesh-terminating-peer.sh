#!/usr/bin/env bash
set -oeu pipefail

# establish peers
ccvp1_port="$(docker inspect ccvp-1-consul-server-1 | jq -r '.[].NetworkSettings.Ports."8501/tcp" | .[].HostPort')"
ccvp2_port="$(docker inspect ccvp-2-consul-server-1 | jq -r '.[].NetworkSettings.Ports."8501/tcp" | .[].HostPort')"

export CONSUL_HTTP_SSL_VERIFY=false
pt="$(consul peering generate-token -name ccvp2-default -http-addr="https://localhost:${ccvp1_port}")"
consul peering establish -name ccvp1-default -peering-token "$pt" -http-addr="https://localhost:${ccvp2_port}"

# deploy external upstream
docker run -d --rm \
  --name ccvp-2-counting-external \
  --hostname ccvp-2-counting-external \
  --network ccvp-flat \
  -e PORT=9999 \
  hashicorp/counting-service:0.0.2
addr="$(docker inspect ccvp-2-counting-external | jq -r '.[].NetworkSettings.Networks."ccvp-flat".IPAddress')"

# deploy terminating gateway
docker run -d \
  --name ccvp-2-consul-tgw-1 \
  --hostname ccvp-2-tgw-1 \
  --network ccvp-flat \
  -e COMPOSE_PROJECT_NAME=ccvp-2 \
  -e CONSUL_GOSSIP_KEY="$(awk -F\" '/^CONSUL_GOSSIP_KEY/ {print $(NF -1)}' .env)" \
  -e CONSUL_HTTP_TOKEN="$(awk -F\" '/^CONSUL_TOKEN/ {print $(NF -1)}' .env)" \
  -e CONSUL_LOCAL_CONFIG='{}' \
  -e GATEWAY_KIND=terminating \
  -e SERVICE_ADDR="$addr" \
  -e SERVICE_PORT=9999 \
  -v ccvp-2_consul_pki:/consul/tls:ro \
  -v ./secrets:/consul/license:ro \
  local/consul-gateway:ccvp


# export
consul config write -http-addr="https://localhost:$ccvp2_port" - <<EOF
Kind      = "exported-services"
Partition = "default"
Name      = "default"
Services = [
  {
    Name      = "counting-ext"
    Consumers = [
      {
        Peer = "ccvp1-default"
      }
    ]
  }
]
EOF


# authorize 
consul config write -http-addr="https://localhost:$ccvp2_port" - <<EOF
Kind      = "service-intentions"
Name      = "counting-ext"
Partition = "default"
Namespace = "default"
Sources = [
  {
    Name      = "dashboard"
    Partition = "default"
    Action    = "allow"
  },
  {
    Name      = "dashboard"
    Peer      = "ccvp1-default"
    Action    = "allow"
  }
]
EOF


# reconfigure dashboard service
docker exec -ti ccvp-1-dashboard-1 bash
curl http://localhost:8500/v1/agent/service/deregister/dashboard-1 --header "X-Consul-Token: $CONSUL_HTTP_TOKEN" --request PUT 
curl http://localhost:8500/v1/agent/service/register \
--header "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
--request PUT \
--data @- <<EOF
{
  "id": "dashboard-1",
  "name": "dashboard",
  "kind": "",
  "port": 8080,
  "check": {
    "name": "service:dashboard-check",
    "deregister_critical_service_after": "3m",
    "status": "critical",
    "http": "http://localhost:8080/health",
    "method": "GET",
    "interval": "1s",
    "timeout": "2s"
  },
  "connect": {
    "sidecar_service": {
      "proxy": {
        "upstreams": [
          {
            "destination_name": "counting-ext",
            "destination_peer": "ccvp2-default",
            "local_bind_port": 9001
          }
        ]
      }
    }
  }
}
EOF