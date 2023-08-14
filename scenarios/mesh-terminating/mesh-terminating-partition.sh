#!/usr/bin/env bash
set -oeu pipefail

ccvp1_port="$(docker inspect ccvp-1-consul-server-1 | jq -r '.[].NetworkSettings.Ports."8501/tcp" | .[].HostPort')"
export CONSUL_HTTP_SSL_VERIFY=false

consul-ent partition create -name=alpha -http-addr="https://localhost:${ccvp1_port}"

# deploy external alpha upstream
docker run -d --rm \
  --name ccvp-1-alpha-counting-external \
  --hostname ccvp-1-alpha-counting-external \
  --network ccvp-flat \
  -e PORT=9999 \
  hashicorp/counting-service:0.0.2
addr="$(docker inspect ccvp-1-alpha-counting-external | jq -r '.[].NetworkSettings.Networks."ccvp-flat".IPAddress')"

# deploy alpha partition terminating gateway
docker run -d \
  --name ccvp-1-alpha-consul-tgw-1 \
  --hostname ccvp-1-alpha-tgw-1 \
  --network ccvp-flat \
  -e COMPOSE_PROJECT_NAME=ccvp-1 \
  -e CONSUL_GOSSIP_KEY="$(awk -F\" '/^CONSUL_GOSSIP_KEY/ {print $(NF -1)}' .env)" \
  -e CONSUL_HTTP_TOKEN="$(awk -F\" '/^CONSUL_TOKEN/ {print $(NF -1)}' .env)" \
  -e CONSUL_LOCAL_CONFIG='{"partition": "alpha"}' \
  -e GATEWAY_KIND=terminating \
  -e CONSUL_PARTITION="alpha" \
  -e SERVICE_ADDR="$addr" \
  -e SERVICE_PORT=9999 \
  -v ccvp-1_consul_pki:/consul/tls:ro \
  -v ./secrets:/consul/license:ro \
  local/consul-gateway:ccvp 

docker run -d --rm \
  --name ccvp-1-alpha-mesh-gateway \
  --hostname ccvp-1-alpha-mesh-gateway-1 \
  --network ccvp-flat \
  -e COMPOSE_PROJECT_NAME=ccvp-1 \
  -e CONSUL_GOSSIP_KEY="$(awk -F\" '/^CONSUL_GOSSIP_KEY/ {print $(NF -1)}' .env)" \
  -e CONSUL_HTTP_TOKEN="$(awk -F\" '/^CONSUL_TOKEN/ {print $(NF -1)}' .env)" \
  -e CONSUL_LOCAL_CONFIG='{"partition": "alpha"}' \
  -e GATEWAY_KIND=mesh \
  -v ccvp-1_consul_pki:/consul/tls:ro \
  -v ./secrets:/consul/license:ro \
  local/consul-gateway:ccvp

curl --insecure --fail-with-body \
--header "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
--request PUT "https://localhost:${ccvp1_port}/v1/config" \
--data @- <<EOF
{
  "kind": "proxy-defaults",
  "name": "global",
  "partition": "alpha",
  "namespace": "default",
  "access_logs": {
    "enabled": true
  },
  "config": {
    "protocol": "http"
  },
  "mesh_gateway": {
    "mode": "local"
  }
}
EOF

#---------------

# export
consul config write -http-addr="https://localhost:$ccvp1_port" - <<EOF
Kind      = "exported-services"
Partition = "alpha"
Name      = "alpha"
Services = [
  {
    Name      = "counting-ext"
    Consumers = [
      {
        Partition = "default"
      }
    ]
  }
]
EOF


# authorize 
consul config write -http-addr="https://localhost:$ccvp1_port" - <<EOF
Kind      = "service-intentions"
Name      = "counting-ext"
Partition = "alpha"
Namespace = "default"
Sources = [
  {
    Name      = "dashboard"
    Partition = "default"
    Action    = "allow"
  },
  {
    Name      = "ingress-gateway"
    Partition = "default"
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
            "destination_partition": "alpha",
            "local_bind_port": 9001 
          }
        ]
      }
    }
  }
}
EOF