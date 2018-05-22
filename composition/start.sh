#!/bin/bash
# check for prereqs
command -v docker >/dev/null 2>&1 || { printf "%s\n" "Docker is required, but does not appear to be installed."; exit; }
test -e _env || { printf "%s\n" "_env file not found"; exit; }
clear

# default values which can be overriden by -f or -p flags
export COMPOSE_FILE=
export COMPOSE_PROJECT_NAME=demo
export $(grep CONSUL_CLUSTER_SIZE _env)

while getopts "f:p:" optchar; do
	case "${optchar}" in
		f) export COMPOSE_FILE=${OPTARG} ;;
		p) export COMPOSE_PROJECT_NAME=${OPTARG} ;;
	esac
done
shift $(( OPTIND - 1 ))

# give the docker remote api more time before timeout
export COMPOSE_HTTP_TIMEOUT=300

echo -e "   ___                      _
  / __\___  _ __  ___ _   _| |
 / /  / _ \| '_ \/ __| | | | |
/ /__| (_) | | | \__ \ |_| | |
\____/\___/|_| |_|___/\__,_|_|"
echo -e "Consul composition"
printf "%s\n" "Starting a ${COMPOSE_PROJECT_NAME} Consul cluster"
printf "\n* Pulling the most recent images\n"
#docker-compose pull
printf "\n* Starting initial container:\n"
docker-compose up -d --remove-orphans --force-recreate

CONSUL_BOOTSTRAP_HOST="${COMPOSE_PROJECT_NAME}_consul_1"

BOOTSTRAP_UI_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONSUL_BOOTSTRAP_HOST")
export CONSUL_BOOTSTRAP_HOST="$BOOTSTRAP_UI_IP"

# Wait for the bootstrap instance
printf ' > Waiting for the bootstrap instance ...'
TIMER=0
until (docker-compose -p "$COMPOSE_PROJECT_NAME" exec consul su-exec consul: test -e /data/node-id)
do
	IS_RESTARTING=$(docker ps --quiet --filter 'status=restarting' --filter "name=${CONSUL_BOOTSTRAP_HOST}" | wc -l)
	if [ "$IS_RESTARTING" -eq 1 ]; then
		exit 1
    elif [ $TIMER -gt 180 ]; then
        exit 1
    fi
    printf '.'
    sleep 3
    TIMER=$(( TIMER + 3))
done
printf "\e[0;32m done\e[0m\n"


# Scale up the cluster
printf "\n%s\n" "* Scaling the Consul raft to ${CONSUL_CLUSTER_SIZE} nodes"
docker-compose -p "$COMPOSE_PROJECT_NAME" up -d --no-recreate --scale consul=$CONSUL_CLUSTER_SIZE

# Wait for Consul to be available
printf ' > Waiting for Consul cluster quorum acquisition and stabilisation ...'
until (docker-compose -p "$COMPOSE_PROJECT_NAME" exec -w /tmp consul sh -c 'consul operator raft list-peers 2>/dev/null|grep -q leader')
do
	printf '.'
	sleep 5
done
printf "\e[0;32m done\e[0m\n"


printf "\n%s\n" '* Bootstrapping Consul ACL system'
set -e

CONSUL_TOKEN=$(docker-compose -p "$COMPOSE_PROJECT_NAME" exec -w /tmp consul sh -c "curl -s -XPUT http://127.0.0.1:8500/v1/acl/bootstrap 2>/dev/null | jq -M -e -c -r '.ID' | tr -d '\000-\037'")
echo -e "Consul ACL token: \e[38;5;198m${CONSUL_TOKEN}\e[0m"

# Install Agent token
printf "%s" ' > Installing Consul agent token ...'
for ((i=1; i <= CONSUL_CLUSTER_SIZE ; i++)); do
	docker-compose -p "$COMPOSE_PROJECT_NAME" exec -e CONSUL_TOKEN=$CONSUL_TOKEN -e AGENT_TOKEN=$CONSUL_TOKEN --index=$i -w /tmp consul sh -c 'curl -s --header "X-Consul-Token: $CONSUL_TOKEN" --data "{\"Token\": \"$CONSUL_TOKEN\"}" -XPUT http://127.0.0.1:8500/v1/agent/token/acl_agent_token'
done
printf "\e[0;32m done\e[0m\n"

printf "%s\n\n" "Consul Dashboard: https://${BOOTSTRAP_UI_IP}:${BOOTSTRAP_UI_PORT:-8501}/ui/"
# Open browser pointing to the Consul UI
command -v open >/dev/null 2>&1 && open "https://$BOOTSTRAP_UI_IP:${BOOTSTRAP_UI_PORT:-8501}/ui/"

