#!/bin/ash

log() {
	printf "%s\n" "$@"|awk '{print strftime("%FT%T%z",systime()),"[INFO] start_consul.sh:",$0}'
}
loge() {
	printf "%s\n" "$@"|awk '{print strftime("%FT%T%z",systime()),"[ERROR] start_consul.sh:",$0}' >&2
}

# Add Consul FQDN to hosts file for convenience
printf "$(hostname -i)\t$(hostname).node.${CONSUL_DNS:-consul}\n" >> /etc/hosts

# Performance configuration
if [ ! "${CONSUL_ENVIRONMENT:-dev}" = 'prod' ]; then
	# Amazon EC2
	if [ -f /sys/hypervisor/uuid ] && [ "$(head -c 3 /sys/hypervisor/uuid)" = 'ec2' ]; then
		EC2_INSTANCE_SIZE=$(wget -q -O- 'http://169.254.169.254/latest/meta-data/instance-type' | awk -F. '{print $2}')
		case "$EC2_INSTANCE_SIZE" in
			nano)   su -s/bin/sh consul -c "{ rm /etc/consul/consul.json; jq '.performance.raft_multiplier = 6' > /etc/consul/consul.json; } < /etc/consul/consul.json" ;;
			micro)  su -s/bin/sh consul -c "{ rm /etc/consul/consul.json; jq '.performance.raft_multiplier = 5' > /etc/consul/consul.json; } < /etc/consul/consul.json" ;;
			small)  su -s/bin/sh consul -c "{ rm /etc/consul/consul.json; jq '.performance.raft_multiplier = 3' > /etc/consul/consul.json; } < /etc/consul/consul.json" ;;
			medium) su -s/bin/sh consul -c "{ rm /etc/consul/consul.json; jq '.performance.raft_multiplier = 2' > /etc/consul/consul.json; } < /etc/consul/consul.json" ;;
			*large) su -s/bin/sh consul -c "{ rm /etc/consul/consul.json; jq '.performance.raft_multiplier = 1' > /etc/consul/consul.json; } < /etc/consul/consul.json" ;;
		esac
	# GCE
	elif [ -f /sys/class/dmi/id/bios_vendor ] && grep -iq "Google" /sys/class/dmi/id/bios_vendor; then
		GCE_INSTANCE_SIZE=$(wget -q -O- 'http://metadata.google.internal/computeMetadata/v1/instance/machine-type')
		case "$GCE_INSTANCE_SIZE" in
			f1-micro) su -s/bin/sh consul -c "{ rm /etc/consul/consul.json; jq '.performance.raft_multiplier = 5' > /etc/consul/consul.json; } < /etc/consul/consul.json" ;;
			g1-small) su -s/bin/sh consul -c "{ rm /etc/consul/consul.json; jq '.performance.raft_multiplier = 3' > /etc/consul/consul.json; } < /etc/consul/consul.json" ;;
			*)        su -s/bin/sh consul -c "{ rm /etc/consul/consul.json; jq '.performance.raft_multiplier = 1' > /etc/consul/consul.json; } < /etc/consul/consul.json" ;;
		esac
	# MS Azure
	elif grep -iq "Hyper-V UEFI" /sys/class/dmi/id/bios_version && AZURE_INSTANCE_SIZE=$(wget -q -O- --header 'Metadata: true' 'http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2017-04-02'); then
		case "$AZURE_INSTANCE_SIZE" in
			Standard_A0) su -s/bin/sh consul -c "{ rm /etc/consul/consul.json; jq '.performance.raft_multiplier = 5' > /etc/consul/consul.json; } < /etc/consul/consul.json" ;;
			Standard_A1) su -s/bin/sh consul -c "{ rm /etc/consul/consul.json; jq '.performance.raft_multiplier = 3' > /etc/consul/consul.json; } < /etc/consul/consul.json" ;;
			Standard_A2) su -s/bin/sh consul -c "{ rm /etc/consul/consul.json; jq '.performance.raft_multiplier = 2' > /etc/consul/consul.json; } < /etc/consul/consul.json" ;;
			*)           su -s/bin/sh consul -c "{ rm /etc/consul/consul.json; jq '.performance.raft_multiplier = 1' > /etc/consul/consul.json; } < /etc/consul/consul.json" ;;
		esac
	fi
fi

# Detect if Consul needs to bind to low ports for DNS
CONSUL_DNS_PORT=$(jq '.ports.dns' /etc/consul/consul.json)
if [ "$CONSUL_DNS_PORT" -le 1024 ]; then # Joyent Triton (Illumos)
	if [ "$(uname -v)" = 'BrandZ virtual linux' ]; then
		# Assign a privilege spec to the process that allows to bind to low ports, chown files,
		# access high resolution timers and change its process id
		/native/usr/bin/ppriv -s LI+NET_PRIVADDR,FILE_CHOWN,PROC_CLOCK_HIGHRES,PROC_SETID $$
	else
		# Assign a linux capability to the Consul binary that allows to bind to low ports
		setcap 'cap_net_bind_service=+ep' /bin/consul
	fi
elif [ "$(uname -v)" = 'BrandZ virtual linux' ]; then
		# Assign a privilege spec to the process that allows to chown files,
		# access high resolution timers and change its process id
		/native/usr/bin/ppriv -s LI+FILE_CHOWN,PROC_CLOCK_HIGHRES,PROC_SETID $$
fi

if [ -e /data/raft/raft.db ]; then
	consul validate /etc/consul/consul.json || exit 1
	# This is a restart
	log "Starting Consul"
	unset CONSUL_ENCRYPT_TOKEN
	unset CONSUL_BOOTSTRAP_HOST
	unset CONSUL_CLUSTER_SIZE

	exec su-exec consul:consul consul agent -server -ui -config-dir=/etc/consul/ -datacenter="$CONSUL_DC_NAME" -domain="${CONSUL_DOMAIN:-consul}" -retry-join="$CONSUL_DNS_NAME" -rejoin
else
	if [ "$CONSUL_DC_NAME" ] && [ "$CONSUL_ENCRYPT_TOKEN" ] && [ "$CONSUL_CLUSTER_SIZE" ] && [ "$CONSUL_DNS_NAME" ]; then
		log "Starting Consul for the first time, using CONSUL_DC_NAME & BOOTSTRAP_HOST environment variables"

		# ACL Datacenter configuration
		if [ -z "$CONSUL_ACL_DC" ]; then
			log "ACL Datacenter not defined, defaulting to $CONSUL_DC_NAME"
			export CONSUL_ACL_DC="$CONSUL_DC_NAME"
		fi

		su -s /bin/sh consul -c "{ rm /etc/consul/consul.json; jq '.acl_datacenter = env.CONSUL_ACL_DC | .acl_agent_master_token = env.CONSUL_ACL_AGENT_MASTER_TOKEN | .acl_agent_token = env.CONSUL_ACL_AGENT_TOKEN | .acl_token = env.CONSUL_ACL_TOKEN' > /etc/consul/consul.json; } < /etc/consul/consul.json"

	# Log Consul bootstrap host to the console
		if [ "${CONSUL_BOOTSTRAP_HOST:-127.0.0.1}" = 127.0.0.1 ]; then
			log "Bootstrap host is $(hostname -s)"
		else
			log "Bootstrap host is ${CONSUL_BOOTSTRAP_HOST}"
		fi

		consul validate /etc/consul/consul.json || exit 1
		exec su-exec consul:consul consul agent -server -ui -config-dir=/etc/consul/ -datacenter="$CONSUL_DC_NAME" -domain="${CONSUL_DOMAIN:-consul}" -bootstrap-expect="$CONSUL_CLUSTER_SIZE" -retry-join="${CONSUL_BOOTSTRAP_HOST:-127.0.0.1}" -retry-join="$CONSUL_DNS_NAME" -encrypt="$CONSUL_ENCRYPT_TOKEN"
	else
		printf "Consul agent configuration\nUsage\n-----\n" >&2
		printf "You must always set the following environment variables to run this container:\nCONSUL_DC_NAME: The desired name for your Consul datacenter\n\n" >&2
		printf "The following environment variables are mandatory only on the first run of the container:\nCONSUL_ENCRYPT_TOKEN: RPC encryption token, can be generated by running consul keygen\nCONSUL_CLUSTER_SIZE: The expected number of server nodes in your cluster\nCONSUL_DNS_NAME: The DNS name for your cluster (eg: consul.service.consul)\n\n" >&2
		printf "The following environment variables are used to configure the cluster (if provided):\nCONSUL_ACL_DC: The Consul ACL Datacenter, defaults to the value of CONSUL_DC_NAME if not provided\nCONSUL_BOOTSTRAP_HOST: A Consul server node to join on startup, only used the first time the container runs. Defaults to 127.0.0.1\nCONSUL_ENVIRONMENT: if set to 'prod', it will configure Consul for high performance. If it is not set and you are running on AWS EC2 or Google Cloud Engine (GCE), a performance setting will be set according to your instance type on the first run of the container\n\n" >&2
		exit 1
	fi
fi
