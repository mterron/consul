FROM mterron/betterscratch
MAINTAINER Miguel Terron <miguel.a.terron@gmail.com>

# Set environment variables
ENV PATH=$PATH:/native/usr/bin:/native/usr/sbin:/native/sbin:/native/bin:/bin

# We don't need to expose these ports in order for other containers on Triton
# to reach this container in the default networking environment, but if we
# leave this here then we get the ports as well-known environment variables
# for purposes of linking.
EXPOSE 53 53/udp 8300 8301 8301/udp 8302 8302/udp 8501 8600 8600/udp

# Copy binaries. bin directory contains startup script
COPY bin/ /bin

# Copy /etc (Consul config, ContainerPilot config)
COPY etc/ /etc

# Download dumb-init
ENV DUMBINIT_VERSION=1.0.2
ADD https://github.com/Yelp/dumb-init/releases/download/v${DUMBINIT_VERSION}/dumb-init_${DUMBINIT_VERSION}_amd64 /
ADD	https://github.com/Yelp/dumb-init/releases/download/v1.0.2/sha256sums /
ENV CONSUL_VERSION=0.6.4
# Download Consul binary
ADD https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip /
# Download Consul integrity file
ADD	https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_SHA256SUMS /

# Create links for needed tools (detects Triton) & install dumb-init
RUN	ln -sf /bin/busybox.static /bin/chmod &&\
	ln -sf /bin/busybox.static /bin/chown &&\
	ln -sf /bin/busybox.static /bin/grep &&\
	ln -sf /bin/busybox.static /bin/ifconfig &&\
	ln -sf /bin/busybox.static /bin/mv &&\
	ln -sf /bin/busybox.static /bin/sleep &&\
# Check integrity and installs dumb-init
	grep dumb-init_${DUMBINIT_VERSION}_amd64|sha256sum -sc &&\
	mv dumb-init_${DUMBINIT_VERSION}_amd64 /bin/dumb-init &&\
	chmod +x /bin/dumb-init &&\
# Check integrity and installs Consul
	grep "linux_amd64.zip" consul_${CONSUL_VERSION}_SHA256SUMS | sha256sum -sc &&\
	unzip -q -o consul_${CONSUL_VERSION}_linux_amd64.zip -d /bin &&\
# Allow Consul to bind to reserved ports (for DNS)
	ssetcap 'cap_net_bind_service=+ep' /bin/consul &&\
# Add CA to system trusted store
	cat /etc/tls/ca.pem >> /etc/ssl/certs/ca-certificates.crt &&\
	touch /etc/ssl/certs/ca-consul.done &&\
# Create Consul data directory
	mkdir /data &&\
	chmod 770 /data &&\
	chown -R consul: /data &&\
	chown -R consul: /etc/consul &&\
# Cleanup
	rm -f /bin/ssetcap &&\
	rm -f /sha256sums &&\
	rm -f consul_${CONSUL_VERSION}_*

# On build provide your own consul dns name on the environment variable CONSUL_DNS_NAME
# and your own certificates
ONBUILD COPY consul.json etc/consul/consul.json
ONBUILD COPY tls/ etc/tls/

# Put Consul data on a separate volume to avoid filesystem performance issues with Docker image layers
VOLUME ["/data"]

USER consul
CMD ["/bin/start_consul.sh"]
