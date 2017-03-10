FROM alpine:3.5
MAINTAINER Miguel Terron <miguel.a.terron@gmail.com>

# Set environment variables
ENV PATH=$PATH:/native/usr/bin:/native/usr/sbin:/native/sbin:/native/bin:/bin \
	CONSUL_VERSION=0.7.5

# Serf LAN and WAN (WAN is used only by Consul servers) are used for gossip between
# Consul agents. LAN is within the datacenter and WAN is between just the Consul
# servers in all datacenters.
EXPOSE 8301 8301/udp 8302 8302/udp

# HTTPS, and DNS (both TCP and UDP) are the primary interfaces that applications
# use to interact with Consul.
EXPOSE 8501 53 53/udp 8600 8600/udp

# Copy binaries. bin directory contains startup script
COPY bin/ /bin

# Copy /etc (Consul config and certificates)
COPY etc/ /etc

# Install wget & libcap
RUN	apk add --no-cache wget libcap ca-certificates su-exec tzdata &&\
	chmod +x /bin/* &&\
# Download Consul binary
	wget -q https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip &&\
# Download Consul integrity file
	wget -q https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_SHA256SUMS &&\
# Check integrity and installs Consul
	grep "consul_${CONSUL_VERSION}_linux_amd64.zip$" consul_${CONSUL_VERSION}_SHA256SUMS | sha256sum -c &&\
	unzip -q -o consul_${CONSUL_VERSION}_linux_amd64.zip -d /bin &&\
# Allows Consul to bind to reserved ports (for DNS)
	setcap 'cap_net_bind_service=+ep' /bin/consul &&\
# Add CA to system trusted store
	cat /etc/tls/ca.pem >> /etc/ssl/certs/ca-certificates.crt &&\
	touch /etc/ssl/certs/ca-consul.done &&\
# Create Consul user
	adduser -H -h /tmp -D -g 'Consul user' -s /dev/null consul &&\
# Create Consul data directory
	mkdir /data &&\
	chown -R consul: /data &&\
	chown -R consul: /etc/consul &&\
	chmod 770 /etc/consul &&\
	chmod 660 /etc/consul/consul.json &&\
	chmod 770 /data &&\
# Cleanup
	rm -f consul_${CONSUL_VERSION}_* sha256sums .ash*

# On build provide your own consul dns name on the environment variable CONSUL_DNS_NAME
# and your own certificates
ONBUILD COPY consul.json /etc/consul/consul.json
ONBUILD COPY tls/ etc/tls/

# When you build on top of this image, put Consul data on a separate volume to
# avoid filesystem performance issues with Docker image layers
#VOLUME ["/data"]

#USER consul
CMD ["/bin/start_consul.sh"]
