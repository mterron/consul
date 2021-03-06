#!/bin/sh
# check for prereqs
command -v docker >/dev/null 2>&1 || { printf 'Docker is required, but does not appear to be installed.'; exit; }
test -e _env || { printf '_env file not found'; exit; }
clear

# default values which can be overriden by -f or -p flags
export COMPOSE_FILE=
export COMPOSE_PROJECT_NAME=demo
export "$(grep CONSUL_CLUSTER_SIZE _env)"

while getopts "f:p:" optchar; do
	case "${optchar}" in
		f) export COMPOSE_FILE=${OPTARG} ;;
		p) export COMPOSE_PROJECT_NAME=${OPTARG} ;;
		*) printf '%s\n' "Unknown option: ${OPTARG}"&&exit 1;;
	esac
done
shift $(( OPTIND - 1 ))

# give the docker remote api more time before timeout
export COMPOSE_HTTP_TIMEOUT=300

printf '   ___                      _
  / __\___  _ __  ___ _   _| |
 / /  / _ \| ´_ \/ __| | | | |
/ /__| (_) | | | \__ \ |_| | |
\____/\___/|_| |_|___/\__,_|_|\n'
printf 'Consul composition\n'
printf '* Pulling the most recent images\n'
docker-compose pull
printf '\n* Starting initial container:\n'
docker-compose up -d --remove-orphans --force-recreate

CONSUL_BOOTSTRAP_HOST="${COMPOSE_PROJECT_NAME}_consul_1"

BOOTSTRAP_UI_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONSUL_BOOTSTRAP_HOST")
export CONSUL_BOOTSTRAP_HOST="$BOOTSTRAP_UI_IP"

# Wait for the bootstrap instance
printf ' > Waiting for the bootstrap instance ...'
TIMER=0
START_TIMEOUT=300
until (docker-compose -p "$COMPOSE_PROJECT_NAME" exec --user=consul consul test -e /data/node-id)
do
	IS_RESTARTING=$(docker ps --quiet --filter 'status=restarting' --filter "name=${CONSUL_BOOTSTRAP_HOST}" | wc -l)
	if [ "$IS_RESTARTING" -eq 1 ]; then
		printf '\e[5;31;40;1mERROR, Consul is restarting. Check the Docker log below:\e[m\n'
        docker logs "$COMPOSE_PROJECT_NAME"_consul_1
		exit 1
    elif [ $TIMER -gt $START_TIMEOUT ]; then
		printf '\e[5;31;40;1mERROR, Vault is taking too long to start. If that is expected please modify $START_TIMEOUT.\e[m\n'
        exit 1
    fi
    printf '.'
    sleep 1
    TIMER=$(( TIMER + 1))
done
printf '\e[0;32m done\e[0m\n'


# Scale up the cluster
printf '\n%s\n' "* Scaling the Consul raft to ${CONSUL_CLUSTER_SIZE} nodes"
docker-compose -p "$COMPOSE_PROJECT_NAME" up -d --no-recreate --scale consul=$CONSUL_CLUSTER_SIZE

# Wait for Consul to be available
printf ' > Waiting for Consul cluster quorum acquisition and stabilisation ...'
until (docker-compose -p "$COMPOSE_PROJECT_NAME" exec -w /tmp consul sh -c 'consul operator raft list-peers 2>/dev/null|grep -q leader')
do
	printf '.'
	sleep 1
done
printf '\e[0;32m done\e[0m\n'


printf '\n* Bootstrapping Consul ACL system\n'
set -e

CONSUL_TOKEN=$(docker-compose -p "$COMPOSE_PROJECT_NAME" exec -w /tmp consul sh -c "consul acl bootstrap grep 'SecretID'|sed 's/SecretID:\s*//g'")
printf "Consul ACL token: \e[38;5;198m${CONSUL_TOKEN}\e[0m\n"

# Install Agent token
printf ' > Installing Consul agent token ...\n'
for i in $(seq $CONSUL_CLUSTER_SIZE); do
	docker-compose -p "$COMPOSE_PROJECT_NAME" exec -e CONSUL_TOKEN="$CONSUL_TOKEN" -e AGENT_TOKEN="$CONSUL_TOKEN" --index=$i -w /tmp consul sh -c 'consul acl set-agent-token master $CONSUL_TOKEN'
done
printf '\e[0;32m done\e[0m\n'

printf '\n%s\n' "Consul Dashboard: https://${BOOTSTRAP_UI_IP}:${BOOTSTRAP_UI_PORT:-8501}/ui/"
# Open browser pointing to the Consul UI
command -v open >/dev/null 2>&1 && open "https://$BOOTSTRAP_UI_IP:${BOOTSTRAP_UI_PORT:-8501}/ui/"
