#!/bin/dumb-init /bin/ash
log() {
	printf "%s\n" "$@"|awk '{print strftime("%FT%T%z",systime()),"[INFO] start_consul.sh:",$0}'
}
loge() {
	printf "%s\n" "$@"|awk '{print strftime("%FT%T%z",systime()),"[ERROR] start_consul.sh:",$0}' >&2
}

/bin/set-timezone.sh
if [ -e /data/raft/raft.db ]; then
	log "Starting Consul"
	unset CONSUL_ENCRYPT_TOKEN
	unset CONSUL_BOOTSTRAP_HOST
	unset CONSUL_CLUSTER_SIZE
	exec /bin/consul agent -server -ui -config-dir=/consul/config/ -dc="$CONSUL_DC_NAME" 
else
	if [ "$CONSUL_DC_NAME" ] && [ "$CONSUL_ENCRYPT_TOKEN" ] && [ "$CONSUL_CLUSTER_SIZE" ] && [ "$CONSUL_BOOTSTRAP_HOST" ] && [ "$CONSUL_DNS_NAME" ]; then
		log "Starting Consul for the first time, using CONSUL_DC_NAME & CONSUL_ENCRYPT_TOKEN & BOOTSTRAP_HOST environment variables"
		if [ -z "$CONSUL_ACL_MASTER_TOKEN" ]; then
			log "Generating acl_master_token"
			if ! CONSUL_ACL_MASTER_TOKEN=$(cat /proc/sys/kernel/random/uuid) 2>/dev/null; then
				CONSUL_ACL_MASTER_TOKEN=$(uuidgen)
			fi
			log "acl_master_token is: $CONSUL_ACL_MASTER_TOKEN, please set this environment variable before starting the rest of the Consul server nodes" 
		fi
		REPLACEMENT_ACL_MASTER_TOKEN=$(printf 's/\"acl_master_token\": .*/"acl_master_token": "%s",/' "$CONSUL_ACL_MASTER_TOKEN")
		sed -i "$REPLACEMENT_ACL_MASTER_TOKEN" /consul/config/consul.json

		if [ -z "$CONSUL_ACL_DC" ]; then
			log "ACL Datacenter not defined, defaulting to $CONSUL_DC_NAME"
			CONSUL_ACL_DC=$CONSUL_DC_NAME
		fi
		CONSUL_ACL_DC=$(echo "$CONSUL_ACL_DC" | tr 'A-Z' 'a-z')
		REPLACEMENT_ACL_DATACENTER=$(printf 's/\"acl_datacenter\": .*/"acl_datacenter": "%s",/' "$CONSUL_ACL_DC")
		sed -i "$REPLACEMENT_ACL_DATACENTER" /consul/config/consul.json
		
		exec /bin/consul agent -server -ui -config-dir=/consul/config/ -dc="$CONSUL_DC_NAME" -encrypt="$CONSUL_ENCRYPT_TOKEN" -bootstrap-expect="$CONSUL_CLUSTER_SIZE" -retry-join="$CONSUL_BOOTSTRAP_HOST" -retry-join="$CONSUL_DNS_NAME"
	else
		printf "Consul agent configuration\nUsage\n-----\n" >&2
		printf "You must always set the following environment variables to run this container:\nCONSUL_DC_NAME: The desired name for your Consul datacenter\n\n" >&2
		printf "The following environment variables are mandatory only on the first run of the container:\nCONSUL_ENCRYPT_TOKEN: RPC encryption token, can be generated by running consul keygen\nCONSUL_CLUSTER_SIZE: The expected number of server nodes in your cluster\nCONSUL_DNS_NAME: The DNS name for your cluster (eg: consul.service.consul)\n\n" >&2
		printf "The following environment variables are used to configure the cluster (if provided):\nCONSUL_ACL_MASTER_TOKEN: Gets assigned to the acl_master_token configuration stanza\nCONSUL_ACL_DC: The Consul ACL Datacenter, defaults to the value of CONSUL_DC_NAME if not provided\nCONSUL_BOOTSTRAP_HOST: A Consul server node to join on startup, only used the first time the container runs\n\n" >&2
		loge "Environment variables not set, aborting"
		exit 1
	fi
fi