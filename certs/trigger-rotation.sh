#!/usr/bin/env bash
set -e

d="$(date -u  +%Y%m%d%H%M%S)"
openssl ecparam -name prime256v1 -genkey -noout -out "ca-key-${d}.pem" 
chmod 444 "ca-key-${d}.pem"

ccvp1_port="$(docker inspect ccvp-1-consul-server-1 | jq -r '.[].NetworkSettings.Ports."8501/tcp" | .[].HostPort')"

curl --insecure --header "X-Consul-Token: $CONSUL_HTTP_TOKEN" --request PUT \
"https://localhost:$ccvp1_port/v1/connect/ca/configuration" \
-d @- <<EOF
{
  "Provider": "consul",
  "Config": {
    "RootCertTTL": "3h",
    "IntermediateCertTTL": "3h",
    "LeafCertTTL": "1h",
    "PrivateKey": "$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' "ca-key-${d}.pem")",
    "PrivateKeyType": "ec",
    "PrivateKeyBits": "256"
  }
}
EOF

exit 0