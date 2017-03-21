#!/bin/bash

# check for prereqs
command -v docker >/dev/null 2>&1 || { printf "%s\n" "Docker is required, but does not appear to be installed."; exit; }

# default values which can be overriden by -f or -p flags
export COMPOSE_FILE=
export COMPOSE_PROJECT_NAME=demo
export CONSUL_CLUSTER_SIZE=3

while getopts "f:p:" optchar; do
	case "${optchar}" in
		f) export COMPOSE_FILE=${OPTARG} ;;
		p) export COMPOSE_PROJECT_NAME=${OPTARG} ;;
	esac
done
shift $(( OPTIND - 1 ))

# give the docker remote api more time before timeout
export COMPOSE_HTTP_TIMEOUT=300

printf "%s\n" 'Starting a Consul service'
printf "%s\n" '>Pulling the most recent images'
#docker-compose pull
# Set initial bootstrap host to localhost
export CONSUL_BOOTSTRAP_HOST=127.0.0.1
printf "%s\n" '>Starting initial container'
docker-compose up -d --remove-orphans


CONSUL_BOOTSTRAP_HOST="${COMPOSE_PROJECT_NAME}_consul_1"
printf "%s\n" "CONSUL_BOOTSTRAP_HOST is $CONSUL_BOOTSTRAP_HOST"

# Default for production
BOOTSTRAP_UI_IP=$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONSUL_BOOTSTRAP_HOST")

BOOTSTRAP_UI_IP="$CONSUL_BOOTSTRAP_HOST"

printf "%s\n" " [DEBUG] BOOTSTRAP_UI_IP is $BOOTSTRAP_UI_IP"
BOOTSTRAP_UI_PORT=$(docker port "$CONSUL_BOOTSTRAP_HOST" | awk -F: '/8501/{print$2}')
printf "%s\n" " [DEBUG] BOOTSTRAP_UI_PORT is $BOOTSTRAP_UI_PORT"

export CONSUL_BOOTSTRAP_HOST=$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONSUL_BOOTSTRAP_HOST")
#CONSUL_BOOTSTRAP_HOST=$(docker inspect --format='{{ .NetworkSettings.IPAddress }}' "$CONSUL_BOOTSTRAP_HOST")

printf "%s\n" " [DEBUG] CONSUL_BOOTSTRAP_HOST is $CONSUL_BOOTSTRAP_HOST"

# Wait for the bootstrap instance
printf '>Waiting for the bootstrap instance...'
TIMER=0
until curl -fs --connect-timeout 1 http://"$BOOTSTRAP_UI_IP":"${BOOTSTRAP_UI_PORT-8500}"/ui &>/dev/null
do
	if [ $TIMER -eq 60 ]; then
		break
	fi
	printf '.'
	sleep 1
	TIMER=$(( TIMER + 1))
done

sleep 5
printf "%s\n" 'The bootstrap instance is now running'
printf "%s\n" "Dashboard: https://$BOOTSTRAP_UI_IP:$BOOTSTRAP_UI_PORT/ui/"
# Open browser pointing to the Consul UI
command -v open >/dev/null 2>&1 && open https://"$BOOTSTRAP_UI_IP":"$BOOTSTRAP_UI_PORT"/ui/

# Scale up the cluster
printf "%s\n" 'Scaling the Consul raft to three nodes'
docker-compose -p "$COMPOSE_PROJECT_NAME" scale consul=$CONSUL_CLUSTER_SIZE
