#!/usr/bin/dumb-init /bin/bash
set -e

#env | grep -e CONSUL -e COMPOSE_PROJECT_NAME

if [ -n "$CONSUL_LOCAL_CONFIG" ]; then
  echo "$CONSUL_LOCAL_CONFIG" > "/consul/config/local.json"
fi

# fork the service
PORT="${DASHBOARD_PORT}" COUNTING_SERVICE_URL="${COUNTING_SERVICE_URL}" /bin/dashboard &

until [[ -r "/consul/tls/consul-agent-ca.pem" && -r "/consul/tls/connect-ca.pem" ]] ; do
  sleep 2
done

# fork a consul process
/bin/consul agent \
-data-dir=/consul/data \
-config-dir=/consul/config \
-datacenter="${COMPOSE_PROJECT_NAME}" \
-encrypt="${CONSUL_GOSSIP_KEY}" \
-retry-join="${COMPOSE_PROJECT_NAME}-consul-server" \
-hcl="acl {
  enabled = true,
  default_policy = \"deny\",
  down_policy = \"extend-cache\",
  tokens { agent = \"${CONSUL_HTTP_TOKEN}\" }
}" \
-hcl='auto_encrypt { tls = true }' \
-hcl='ports { grpc_tls = 8502, serf_wan = -1 }' \
-hcl='tls {
  defaults {
    ca_file = "/consul/tls/consul-agent-ca.pem",
    verify_incoming = false,
    verify_outgoing = true
  },
  grpc {
    use_auto_cert = false
  },
  internal_rpc {
    verify_incoming = true,
    verify_server_hostname = true
  }
}' &

until curl --silent --fail --header "X-Consul-Token: $CONSUL_HTTP_TOKEN" http://localhost:8500/v1/status/leader | grep -qE '(\.|:)+' ; do
  sleep 2
done

# register consul service
# https://developer.hashicorp.com/consul/api-docs/agent/service
# https://developer.hashicorp.com/consul/api-docs/agent/check#register-check
# https://developer.hashicorp.com/consul/api-docs/agent/service#connect-structure
curl http://localhost:8500/v1/agent/service/register \
--header "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
--request PUT \
--data @- <<EOF
{
  "id": "dashboard-1",
  "name": "dashboard",
  "kind": "",
  "port": ${DASHBOARD_PORT},
  "check": {
    "name": "service:dashboard-check",
    "deregister_critical_service_after": "3m",
    "status": "critical",
    "http": "http://localhost:${DASHBOARD_PORT}/health",
    "method": "GET",
    "interval": "1s",
    "timeout": "2s"
  },
  "connect": {
    "sidecar_service": {
      "proxy": {
        "upstreams": [
          {
            "destination_name": "counting",
            "local_bind_port": ${COUNTING_SERVICE_URL##*:}
          }
        ]
      }
    }
  }
}
EOF

# fork envoy process, wrapped by consul helper to generate bootstrap config
consul connect envoy -sidecar-for="dashboard-1" -admin-bind="127.0.0.1:19000" -grpc-ca-file="/consul/tls/connect-ca.pem" &


# cant stop, wont stop...
wait


exit 0
