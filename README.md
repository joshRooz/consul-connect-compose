# Consul Connect - Vault Provider
For the purposes of demonstration and testing - builds and deploys two Docker Compose projects `ccvp-1` and `ccvp-2` into a single bridge network. Each consists of a Consul Datacenter and Vault Cluster. Change the `.env` contents at the root of the repository to build and test different versions/combinations.

Consul is bootstrapped with shortened TTLs for the internal CA specified. Vault is configured as the Connect CA immediately following (see `config` service).

Counting and Dashboard services are deployed to containers that fork three processes (`consul`, `envoy`, `service`).

L7 intentions are enabled for `dashboard` to make requests to `http://<counting-upstream>/`. The counting service's node drops all requests where the source is *not* `localhost`.


> *Note*: `make` uses the `compose` plugin as opposed to `docker-compose` standalone binary. `make` and scripts are also hard-coded for `ccvp-1` and `ccvp-2`

# Scenarios
There are command snippets in the `scenarios/` directory that showcase the *possible* combinations for service mesh usage. The aim is to provide a guide for stepping through **manually** (ie: there's no idempotency, and running different combinations will surely encounter collisions). The containers for any scenarios that are manually executed should be cleaned up before running `make down`. 

# Usage

## Deploy
```sh
make up
```

## Peer, Test, etc
```sh
# do.things.
```

## Destroy
```sh
make down
```

# Connect CA 
## Connect CA - Vault
*with modified TTL on Consul CA at bootstrap*
```sh
# get the cross-signed ca root
curl -s -k -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" $CONSUL_HTTP_ADDR/v1/agent/connect/ca/roots  | jq
```

## Inspecting a Service
```sh
# get the chain
docker exec ccvp-1-counting-1 curl -s -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" 127.0.0.1:8500/v1/agent/connect/ca/leaf/counting | jq -r .CertPEM |
  openssl crl2pkcs7 -nocrl -certfile /dev/stdin | openssl pkcs7 -print_certs -noout

# get the leaf cert
docker exec ccvp-1-counting-1 curl -s -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" 127.0.0.1:8500/v1/agent/connect/ca/leaf/counting | jq -r .CertPEM |
  openssl x509 -noout -text
```
