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
