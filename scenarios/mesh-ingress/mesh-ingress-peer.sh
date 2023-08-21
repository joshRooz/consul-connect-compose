#!/usr/bin/env bash
set -oeu pipefail

# establish peers
ccvp1_port="$(docker inspect ccvp-1-consul-server-1 | jq -r '.[].NetworkSettings.Ports."8501/tcp" | .[].HostPort')"
ccvp2_port="$(docker inspect ccvp-2-consul-server-1 | jq -r '.[].NetworkSettings.Ports."8501/tcp" | .[].HostPort')"

export CONSUL_HTTP_SSL_VERIFY=false
pt="$(consul peering generate-token -name ccvp2-default -http-addr="https://localhost:${ccvp1_port}")"
consul peering establish -name ccvp1-default -peering-token "$pt" -http-addr="https://localhost:${ccvp2_port}"

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
  -p 9998:9998/tcp \
  -e PORT=9998 \
  -e COUNTING_SERVICE_URL="http://counting.ingress.consul:9003" \
  hashicorp/dashboard-service:0.0.4


#---------------
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
        Name = "counting"
        Peer = "ccvp2-default"
      }
    ]
  }
]
EOF

# export
consul config write -http-addr="https://localhost:$ccvp2_port" - <<EOF
Kind      = "exported-services"
Partition = "default"
Name      = "default"
Services = [
  {
    Name      = "counting"
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
Name      = "counting"
Partition = "default"
Namespace = "default"
Sources = [
  {
    Name      = "dashboard"
    Action    = "allow"
  },
  {
    Name      = "ingress-gateway"
    Peer      = "ccvp1-default"
    Action    = "allow"
  }
]
EOF
