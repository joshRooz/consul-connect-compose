#!/usr/bin/env bash
set -oeu pipefail

# establish peers
ccvp1_port="$(docker inspect ccvp-1-consul-server-1 | jq -r '.[].NetworkSettings.Ports."8501/tcp" | .[].HostPort')"
ccvp2_port="$(docker inspect ccvp-2-consul-server-1 | jq -r '.[].NetworkSettings.Ports."8501/tcp" | .[].HostPort')"

export CONSUL_HTTP_SSL_VERIFY=false
pt="$(consul peering generate-token -name ccvp2-default -http-addr="https://localhost:${ccvp1_port}")"
consul peering establish -name ccvp1-default -peering-token "$pt" -http-addr="https://localhost:${ccvp2_port}"

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

# deploy external downstream --
docker run -d --rm \
  --name ccvp-1-dashboard-external \
  --hostname ccvp-1-dashboard-external \
  --network ccvp-flat \
  --add-host counting.bridge.internal:$agw_addr \
  -p 9998:9998/tcp \
  -e PORT=9998 \
  -e COUNTING_SERVICE_URL="http://counting.bridge.internal:8080" \
  hashicorp/dashboard-service:0.0.4


#---------------
# add http-route
consul config write -http-addr="https://localhost:$ccvp1_port" - <<-EOF
Kind = "http-route"
Name = "counting-http-route"
Hostnames = [
  "counting.bridge.internal",
  "counting.default.bridge.internal",
  "counting.default.ccvp1.bridge.internal",
  "counting.default.ccvp2.bridge.internal",
]

Parents = [
  {
    Kind        = "api-gateway"
    Name        = "api-gateway"
    SectionName = "http-listener"
  }
]

# Note there is no circuit breaking when weights are assigned
Rules = [
  {
    Matches = [{
      Headers = [
        { Match = "prefix", Name = "Host", Value = "counting.default.ccvp1" }
      ]
    }]
    Services = [
      { Name = "counting" }
    ]
  },
  {
    Matches = [{
      Headers = [
        { Match = "prefix", Name = "Host", Value = "counting.default.ccvp2" }
      ]
    }]
    Services = [
      { Name = "counting-ccvp2" }
    ]
  },
  {
    # without weights assigned appears to be split evenly
    Services = [
      { Name = "counting", Weight = 90 },
      { Name = "counting-ccvp2", Weight = 10 }
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

# service-resolver
consul config write -http-addr="https://localhost:$ccvp1_port" - <<EOF
Kind      = "service-resolver"
Partition = "default"
Name      = "counting-ccvp2"
Redirect = {
  Service = "counting"
  Peer = "ccvp2-default"
}
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
    Name      = "api-gateway"
    Peer      = "ccvp1-default"
    Action    = "allow"
  }
]
EOF
