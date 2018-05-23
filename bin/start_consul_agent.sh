#!/bin/ash

log() {
	printf '%s\n' "$@"|awk '{print strftime("%FT%T%z",systime()),"[INFO] start_consul.sh:",$0}'
}
logd() {
	if [ ${DEBUG:-} ]; then
		printf '%s\n' "$@"|awk '{print strftime("%FT%T%z",systime()),"[DEBUG] start_consul.sh:",$0}'
	fi
}

set_consul_performance() {
	PERFORMANCE=$1 su -s /bin/sh consul -c "{ rm /etc/consul/consul.json;jq '.performance.raft_multiplier=(env.PERFORMANCE|tonumber)' >/etc/consul/consul.json; } < /etc/consul/consul.json"
}

# Add Consul FQDN to hosts file for convenience
#printf '%s\t%s\n' "$(hostname -i)" "$(hostname).node.${CONSUL_DOMAIN:-consul}" >> /etc/hosts

# Performance configuration for Cloud providers
# See https://www.consul.io/docs/guides/performance.html
if [ "${CONSUL_PERFORMANCE:=auto}" = 'max' ]; then
	set_consul_performance 1
elif [ "$CONSUL_PERFORMANCE" = 'auto' ]; then
	# Amazon EC2
	if [ -f /sys/hypervisor/uuid ] && [ "$(head -c 3 /sys/hypervisor/uuid | tr '[:lower:]' '[:upper:]')" = 'EC2' ]; then
		EC2_INSTANCE-TYPE="$(wget -q -O- 'http://169.254.169.254/latest/meta-data/instance-type' | awk -F. '{print $2}')"
		case "${EC2_INSTANCE-TYPE}" in
			nano)   set_consul_performance 6 ;;
			micro)  set_consul_performance 5 ;;
			small)  set_consul_performance 3 ;;
			medium) set_consul_performance 2 ;;
			*large) set_consul_performance 1 ;;
		esac
	# GCE
	elif [ -f /sys/class/dmi/id/bios_vendor ] && grep -iq 'Google' /sys/class/dmi/id/bios_vendor; then
		GCE_MACHINE-TYPE="$(wget -q -O- --header 'Metadata-Flavor: Google' 'http://metadata.google.internal/computeMetadata/v1/instance/machine-type'| awk -F/ '{print $NF}')"
		case "${GCE_MACHINE-TYPE}" in
			f1-micro) set_consul_performance 5 ;;
			g1-small) set_consul_performance 3 ;;
			*)        set_consul_performance 1 ;;
		esac
	# MS Azure
	elif [ -f /sys/class/dmi/id/bios_vendor ] && grep -iq 'Hyper-V UEFI' /sys/class/dmi/id/bios_version; then
		AZURE_VMSIZE="$(wget -q -O- --header 'Metadata: true' 'http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2017-04-02')"
		case "${AZURE_VMSIZE}" in
			Standard_A0) set_consul_performance 5 ;;
			Standard_A1) set_consul_performance 3 ;;
			Standard_A2) set_consul_performance 2 ;;
			*)           set_consul_performance 1 ;;
		esac
	fi
else
	log "Can't determine performance settings. Using Consul default settings"
fi

# Detect if we are running on Joyent Triton (Illumos)
# Assign a privilege spec to the process that allows it to chown files,
# access high resolution timers and change its process id
if [ "$(uname -v)" = 'BrandZ virtual linux' ]; then
	/native/usr/bin/ppriv -s LI+FILE_CHOWN,PROC_CLOCK_HIGHRES,PROC_SETID $$
fi

# Detect if Consul needs to bind to low ports
CONSUL_LOWEST_PORT=$(jq '.ports|map(numbers)|min' /etc/consul/consul.json)
if [ "$CONSUL_LOWEST_PORT" -le 1024 ]; then
	if [ "$(uname -v)" = 'BrandZ virtual linux' ]; then # Joyent Triton (Illumos)
		# Assign a privilege spec to the process that allows it to bind to low ports
		/native/usr/bin/ppriv -s LI+NET_PRIVADDR $$
	else
		# Assign a linux capability to the Consul binary that allows it to bind to low ports
		setcap 'cap_net_bind_service=+ep' /usr/local/bin/consul
	fi
fi

if [ -e "/data/raft/raft.db" ]; then # This is a restart
# Bug in 1.0.6 fails if the key data_dir is not included
#	consul validate -quiet /etc/consul/consul.json || exit 1
	logd 'Starting Consul'
	unset CONSUL_ENCRYPT_TOKEN

	exec -a consul su-exec consul:consul consul agent -config-dir=/etc/consul/ -data-dir=/data -datacenter="$CONSUL_DC_NAME" -domain="${CONSUL_DOMAIN:=consul}" -retry-join="$CONSUL_DNS_NAME" -rejoin
else
		# Create Consul's data directory
		mkdir -p -m 775 /data
		chown -R consul: /data

		# ACL Datacenter configuration
		if [ -z "$CONSUL_ACL_DC" ]; then
			log "ACL Datacenter not defined, defaulting to $CONSUL_DC_NAME"
			export CONSUL_ACL_DC="$CONSUL_DC_NAME"
		fi
		su -s /bin/sh consul -c "{ rm /etc/consul/consul.json; jq '.acl_datacenter = env.CONSUL_ACL_DC' > /etc/consul/consul.json; } < /etc/consul/consul.json"

		exec -a consul su-exec consul:consul consul agent -config-dir=/etc/consul/ -data-dir=/data -datacenter="$CONSUL_DC_NAME" -domain="${CONSUL_DOMAIN:=consul}" -retry-join=consul -retry-join="${CONSUL_BOOTSTRAP_HOST:-127.0.0.1}" -retry-join="$CONSUL_DNS_NAME" -encrypt="$CONSUL_ENCRYPT_TOKEN"
	else
		exit 1
	fi
fi
