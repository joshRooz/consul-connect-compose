#!/bin/bash
set -eou pipefail

#env | grep -e CONSUL -e VAULT -e COMPOSE_PROJECT_NAME

# generate consul agent ca and leaf cert for the server instance
if [ ! -s "${COMPOSE_PROJECT_NAME}-server-consul-0.pem" ]  ; then
  cd /consul-pki
  consul tls ca create
  consul tls cert create -server -dc="${COMPOSE_PROJECT_NAME}" -additional-dnsname="${COMPOSE_PROJECT_NAME}-consul-server"
  chown 100:1000 "${COMPOSE_PROJECT_NAME}-server-consul-0.pem" "${COMPOSE_PROJECT_NAME}-server-consul-0-key.pem"
fi

cnt=1
until curl --fail --silent "${VAULT_ADDR}/v1/sys/health" >/dev/null ; do
  sleep $((cnt *= 2 ))
done

# create Vault policies used by Consul - Consul Managed PKI in this instance
echo 'path "sys/mounts/cc_root" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "sys/mounts/cc_signing" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "sys/mounts/cc_signing/tune" {
  capabilities = ["update"]
}
path "/cc_root/*" {
  capabilities = [ "create", "read", "update", "delete", "list" ]
}
path "/cc_signing/*" {
  capabilities = [ "create", "read", "update", "delete", "list" ]
}
path "auth/token/renew-self" {
  capabilities = [ "update" ]
}
path "auth/token/lookup-self" {
  capabilities = [ "read" ]
}' | vault policy write consul-connect-ca -

ccvp_token="$(vault token create -policy=consul-connect-ca -orphan -field=token)"


# apply config to consul once leader is established
cnt=1
until curl --fail --silent --insecure "${CONSUL_HTTP_ADDR}/v1/status/leader" | grep -q :8300
do
  sleep $((cnt *= 2 ))
done

curl --insecure --fail-with-body \
--header "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
--request PUT "${CONSUL_HTTP_ADDR}/v1/connect/ca/configuration" \
--data @- <<EOF
{
  "Provider": "vault",
  "Config": {
      "Address": "${VAULT_ADDR}",
      "Token": "${ccvp_token}",
      "RootPKIPath": "cc_root",
      "IntermediatePKIPath": "cc_signing",
      "LeafCertTTL": "72h",
      "IntermediateCertTTL": "8760h",
      "RootCertTTL": "87600h",
      "PrivateKeyType": "ec",
      "PrivateKeyBits": 256
  },
  "ForceWithoutCrossSigning": false
}
EOF

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

until curl --fail --silent "${VAULT_ADDR}/v1/cc_signing/ca_chain" | tee /consul-pki/connect-ca.pem ; do
  sleep 2
done


exit 0
