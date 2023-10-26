#!/usr/bin/env bash
set -oeu pipefail

ccvp1_port="$(docker inspect ccvp-1-consul-server-1 | jq -r '.[].NetworkSettings.Ports."8501/tcp" | .[].HostPort')"
export CONSUL_HTTP_SSL_VERIFY=false

consul-ent partition create -name=alpha -http-addr="https://localhost:${ccvp1_port}"

# deploy alpha partition upstream
docker run -d --rm \
  --name ccvp-1-alpha-counting \
  --hostname ccvp-1-alpha-counting \
  --network ccvp-flat \
  --privileged \
  -e COMPOSE_PROJECT_NAME=ccvp-1 \
  -e CONSUL_GOSSIP_KEY="$(awk -F\" '/^CONSUL_GOSSIP_KEY/ {print $(NF -1)}' .env)" \
  -e CONSUL_HTTP_TOKEN="$(awk -F\" '/^CONSUL_TOKEN/ {print $(NF -1)}' .env)" \
  -e COUNTING_PORT=9999 \
  -e CONSUL_LOCAL_CONFIG='{"partition": "alpha"}' \
  -v ccvp-1_consul_pki:/consul/tls:ro \
  -v ./secrets:/consul/license:ro \
  local/counting:ccvp
addr="$(docker inspect ccvp-1-alpha-counting | jq -r '.[].NetworkSettings.Networks."ccvp-flat".IPAddress')"

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

#--------------------------
# deploy api gateway
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

consul config write -http-addr="https://localhost:$ccvp1_port" - <<EOF
Kind = "http-route"
Name = "counting-alpha-http-route"
Hostnames = ["counting.alpha.bridge.internal"]

Parents = [
  {
    Kind        = "api-gateway"
    Name        = "api-gateway"
    SectionName = "http-listener"
  }
]

Rules = [
  {
    Services = [
      {
        Name   = "counting"
        Partition = "alpha"
      }
    ]
  }
]
EOF

# deploy external downstream --
docker run -d --rm \
  --name ccvp-1-dashboard-external \
  --hostname ccvp-1-dashboard-external \
  --network ccvp-flat \
  --add-host counting.alpha.bridge.internal:$agw_addr \
  -p 9998:9998/tcp \
  -e PORT=9998 \
  -e COUNTING_SERVICE_URL="http://counting.alpha.bridge.internal:8080" \
  hashicorp/dashboard-service:0.0.4

# export
#consul config write -http-addr="https://localhost:$ccvp1_port" - <<EOF
#Kind      = "exported-services"
#Partition = "alpha"
#Name      = "alpha"
#Services = [
#  {
#    Name      = "counting"
#    Consumers = [
#      {
#        Partition = "default"
#      }
#    ]
#  }
#]
#EOF

# authorize 
consul config write -http-addr="https://localhost:$ccvp1_port" - <<EOF
Kind      = "service-intentions"
Name      = "counting"
Partition = "alpha"
Namespace = "default"
Sources = [
  {
    Name      = "api-gateway"
    Partition = "default"
    Action    = "allow"
  }
]
EOF








