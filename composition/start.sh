#!/bin/bash

# check for prereqs
command -v docker >/dev/null 2>&1 || { printf "%s\n" "Docker is required, but does not appear to be installed. See https://docs.joyent.com/public-cloud/api-access/docker"; exit; }

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

echo -e "Consul composition\e[m"

printf "%s\n" 'Starting a Consul service'
printf "%s\n" '>Pulling the most recent images'
docker-compose pull
# Set initial bootstrap host to localhost
export CONSUL_BOOTSTRAP_HOST=127.0.0.1
printf "%s\n" '>Starting initial container'
docker-compose up -d --remove-orphans


CONSUL_BOOTSTRAP_HOST="${COMPOSE_PROJECT_NAME}_consul_1"
printf "%s\n" "CONSUL_BOOTSTRAP_HOST is $CONSUL_BOOTSTRAP_HOST"

# Default for production
export BOOTSTRAP_UI_IP=$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONSUL_BOOTSTRAP_HOST")
# For running on local docker-machine
#if ! BOOTSTRAP_UI_IP=$(docker-machine ip); then {
#	BOOTSTRAP_UI_IP=127.0.0.1
#}
#fi

printf "%s\n" " [DEBUG] BOOTSTRAP_UI_IP is $BOOTSTRAP_UI_IP"
#BOOTSTRAP_UI_PORT=$(docker port "$CONSUL_BOOTSTRAP_HOST" | awk -F: '/8501/{print$2}')
BOOTSTRAP_UI_PORT=8501
printf "%s\n" " [DEBUG] BOOTSTRAP_UI_PORT is $BOOTSTRAP_UI_PORT"

# Wait for the bootstrap instance
# This fails in MACVLAN based environments as there's no connectivity between
# host and containers. 30s should be enough to ensure the instance is up, but
# should check for docker status too.
printf '>Waiting for the bootstrap instance...'
TIMER=0
until curl -fs --connect-timeout 1 http://"$BOOTSTRAP_UI_IP":"${BOOTSTRAP_UI_PORT:-8501}"/ui &>/dev/null
do
	IS_RESTARTING=$(docker ps --quiet --filter 'status=restarting' --filter "name=${COMPOSE_PROJECT_NAME}_consul_1" | wc -l)
	if [ "$IS_RESTARTING" -eq 1 ]; then
		break
	elif [ $TIMER -eq 30 ]; then
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
docker-compose -p "$COMPOSE_PROJECT_NAME" up -d --no-recreate --scale consul=$CONSUL_CLUSTER_SIZE
printf "%s\n" 'Bootstrapping Consul ACL system'
docker run -it --rm  -v $(pwd):/tmp --network=macvlan alpine:latest sh -c "apk --no-cache -q add curl jq && cd /tmp && echo \"BOOTSTRAP HOST IP IS: $BOOTSTRAP_UI_IP\" && echo \"$BOOTSTRAP_UI_IP consul.service.consul\" >> /etc/hosts &&echo -n -e \"@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\n@ ACL Master Token is: \e[1;37m\$(curl -fs --cert client_certificate.pem --cert-type PEM --key client_certificate.key --cacert ca.pem -k -XPUT 'https://consul.service.consul:8501/v1/acl/bootstrap' | jq --compact-output --raw-output '.ID')\e[0m @\n@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\n\""


