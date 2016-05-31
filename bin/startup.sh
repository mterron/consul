#!/bin/dumb-init /bin/ash
log() {
    printf "%s\n" "$@"|awk '{print strftime("%FT%T%z",systime()),"[INFO] startup.sh:",$0}'
}
loge() {
    printf "%s\n" "$@"|awk '{print strftime("%FT%T%z",systime()),"[ERROR] startup.sh:",$0}'
}
###################################################################################################
/bin/set-timezone.sh
if [ -e /data/raft/raft.db ]; then
	log "Starting up Consul"
	unset CONSUL_ENCRYPT_TOKEN
	unset BOOTSTRAP_HOST
	exec /bin/consul agent -server -config-dir=/etc/consul/ -dc="$CONSUL_DC_NAME" 
else
	log "Starting up Consul for the first time, using CONSUL_ENCRYPT_TOKEN & BOOTSTRAP_HOST environment variables"
	if [ "$CONSUL_ENCRYPT_TOKEN" ]; then
		exec /bin/consul agent -server -config-dir=/etc/consul/ -dc="$CONSUL_DC_NAME" -bootstrap-expect="$CONSUL_CLUSTER_SIZE" -retry-join="$CONSUL_BOOTSTRAP_HOST" -retry-join="$CONSUL_DNS_NAME" -encrypt="$CONSUL_ENCRYPT_TOKEN"
	else
		loge "CONSUL_ENCRYPT_TOKEN not set, aborting"
		exit 1
	fi
fi
