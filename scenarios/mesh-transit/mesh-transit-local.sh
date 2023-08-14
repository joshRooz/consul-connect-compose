#!/usr/bin/env bash
set -oeu pipefail

ccvp1_port="$(docker inspect ccvp-1-consul-server-1 | jq -r '.[].NetworkSettings.Ports."8501/tcp" | .[].HostPort')"
export CONSUL_HTTP_SSL_VERIFY=false

# deploy external upstream
docker run -d --rm \
  --name ccvp-1-counting-external \
  --hostname ccvp-1-counting-external \
  --network ccvp-flat \
  -e PORT=9999 \
  hashicorp/counting-service:0.0.2
addr="$(docker inspect ccvp-1-counting-external | jq -r '.[].NetworkSettings.Networks."ccvp-flat".IPAddress')"

# deploy terminating gateway
docker run -d \
  --name ccvp-1-consul-tgw \
  --hostname ccvp-1-tgw \
  --network ccvp-flat \
  -e COMPOSE_PROJECT_NAME=ccvp-1 \
  -e CONSUL_GOSSIP_KEY="$(awk -F\" '/^CONSUL_GOSSIP_KEY/ {print $(NF -1)}' .env)" \
  -e CONSUL_HTTP_TOKEN="$(awk -F\" '/^CONSUL_TOKEN/ {print $(NF -1)}' .env)" \
  -e GATEWAY_KIND=terminating \
  -e SERVICE_ADDR="$addr" \
  -e SERVICE_PORT=9999 \
  -v ccvp-1_consul_pki:/consul/tls:ro \
  -v ./secrets:/consul/license:ro \
  local/consul-gateway:ccvp 


#--------------------------
# deploy ingress gateway - replace with api gateway
docker run -d \
  --name ccvp-1-consul-igw \
  --hostname ccvp-1-igw \
  --network ccvp-flat \
  -e COMPOSE_PROJECT_NAME=ccvp-1 \
  -e CONSUL_GOSSIP_KEY="$(awk -F\" '/^CONSUL_GOSSIP_KEY/ {print $(NF -1)}' .env)" \
  -e CONSUL_HTTP_TOKEN="$(awk -F\" '/^CONSUL_TOKEN/ {print $(NF -1)}' .env)" \
  -e GATEWAY_KIND=ingress \
  -e SERVICE_ADDR="$addr" \
  -e SERVICE_PORT=8888 \
  -v ccvp-1_consul_pki:/consul/tls:ro \
  -v ./secrets:/consul/license:ro \
  local/consul-gateway:ccvp 
igw_addr="$(docker inspect ccvp-1-consul-igw | jq -r '.[].NetworkSettings.Networks."ccvp-flat".IPAddress')"

# deploy external downstream --
docker run -d --rm \
  --name ccvp-1-dashboard-external \
  --hostname ccvp-1-dashboard-external \
  --network ccvp-flat \
  --add-host counting.ingress.consul:$igw_addr \
  --add-host counting-ext.ingress.consul:$igw_addr \
  -p 9998:9998/tcp \
  -e PORT=9998 \
  -e COUNTING_SERVICE_URL="http://counting-ext.ingress.consul:9002" \
  hashicorp/dashboard-service:0.0.4


#---------------
# authorize 
consul config write -http-addr="https://localhost:$ccvp1_port" - <<EOF
Kind      = "service-intentions"
Name      = "counting-ext"
Partition = "default"
Sources = [
  {
  Name = "ingress-gateway"
  Action = "allow"
  }
]
EOF
