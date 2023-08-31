.PHONY: up down show-ports show-network show-ca-root-cert show-counting-leaf-cert trigger-root-rotation

up:
	docker network create ccvp-flat
	docker compose up -d
	docker compose -p ccvp-2 up -d
	docker ps --format=json | jq -r '[.Names,.Ports] | @tsv'

down:
	docker compose down
	docker compose -p ccvp-2 down
	docker network rm ccvp-flat
	docker volume prune -f
	docker volume ls -q | grep ccvp | xargs docker volume rm
	docker rmi local/config:ccvp local/consul-gateway:ccvp local/counting:ccvp local/dashboard:ccvp


show-ports:
	docker ps --format=json | jq -sr '[ .[] | [.Names,.Ports]] | sort | .[] | @tsv'

show-network:
	docker inspect ccvp-flat | jq -r '[.[].Containers | .[] | [.Name,.IPv4Address]] | sort | .[] | @tsv'

show-ca-root-cert:
	docker exec ccvp-1-consul-server-1 curl -s -H "X-Consul-Token: $$CONSUL_HTTP_TOKEN" 127.0.0.1:8500/v1/agent/connect/ca/roots | jq -r .Roots[].RootCert | openssl x509 -noout -text | grep -E '^|Not (Before|After)|X509v3 Subject Key Identifier'

show-counting-leaf-cert:
	docker exec ccvp-1-consul-server-1 curl -s -H "X-Consul-Token: $$CONSUL_HTTP_TOKEN" 127.0.0.1:8500/v1/agent/connect/ca/leaf/counting | jq -r .CertPEM | openssl x509 -noout -text | grep -E '^|Not (Before|After)|X509v3 (Subject|Authority) Key Identifier'

trigger-root-rotation:
	pushd certs; \
	./trigger-rotation.sh; \
	popd
