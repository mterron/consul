#!/bin/dumb-init /bin/ash
log() {
	printf "%s\n" "$@"|awk '{print strftime("%FT%T%z",systime()),"[INFO] startup.sh:",$0}'
}
loge() {
	printf "%s\n" "$@"|awk '{print strftime("%FT%T%z",systime()),"[ERROR] startup.sh:",$0}' >&2
}

/bin/set-timezone.sh
if [ -e /data/raft/raft.db ]; then
	log "Starting Consul"
	unset CONSUL_ENCRYPT_TOKEN
	unset BOOTSTRAP_HOST
	exec /bin/consul agent -server -ui -config-dir=/etc/consul/ -dc="$CONSUL_DC_NAME" 
else
	if [ "$CONSUL_DC_NAME" ] && [ "$CONSUL_ENCRYPT_TOKEN" ] && [ "$CONSUL_CLUSTER_SIZE" ] && [ "$CONSUL_BOOTSTRAP_HOST" ] && [ "$CONSUL_DNS_NAME" ]; then
		log "Starting Consul for the first time, using CONSUL_DC_NAME & CONSUL_ENCRYPT_TOKEN & BOOTSTRAP_HOST environment variables"
		exec /bin/consul agent -server -ui -config-dir=/etc/consul/ -dc="$CONSUL_DC_NAME" -encrypt="$CONSUL_ENCRYPT_TOKEN" -bootstrap-expect="$CONSUL_CLUSTER_SIZE" -retry-join="$CONSUL_BOOTSTRAP_HOST" -retry-join="$CONSUL_DNS_NAME"
	else
		printf "Usage:\nYou need to set the following environment variables to run this container:\nCONSUL_DC_NAME\nCONSUL_ENCRYPT_TOKEN\nCONSUL_CLUSTER_SIZE\nCONSUL_DNS_NAME\n"
		loge "Environment variables not set, aborting"
		exit 1
	fi
fi
