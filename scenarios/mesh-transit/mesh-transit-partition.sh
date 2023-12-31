#!/usr/bin/env bash
set -oeu pipefail

# establish peers
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
  -e COUNTING_SERVICE_URL="http://counting-ext.ingress.consul:9003" \
  hashicorp/dashboard-service:0.0.4

# ingress add listener
consul config write -http-addr="https://localhost:$ccvp1_port" - <<-EOF
Kind = "ingress-gateway"
Name = "ingress-gateway"
Listeners = [
  {
    Port = 9002
    Protocol = "http"
    Services = [
      {
        Name = "counting-ext"
      },
      {
        Name = "counting"
      }
    ]
  },
  {
    Port = 9003
    Protocol = "http"
    Services = [
      {
        Name      = "counting"
        Partition = "alpha"
      },
      {
        Name      = "counting-ext"
        Partition = "alpha"
      }
    ]
  }
]
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

