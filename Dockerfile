FROM mterron/betterscratch
MAINTAINER Miguel Terron <miguel.a.terron@gmail.com>

# Set environment variables
ENV PATH=$PATH:/native/usr/bin:/native/usr/sbin:/native/sbin:/native/bin:/bin \
	DUMBINIT_VERSION=1.1.3 \
	CONSUL_VERSION=0.7.0

# We don't need to expose these ports in order for other containers on Triton
# to reach this container in the default networking environment, but if we
# leave this here then we get the ports as well-known environment variables
# for purposes of linking.
EXPOSE 53 53/udp 8300 8301 8301/udp 8302 8302/udp 8501 8600 8600/udp

# Copy binaries. bin directory contains startup script
COPY bin/ /bin

# Copy /etc (Consul config and certificates)
COPY etc/ /etc

# Download dumb-init
RUN wget -q https://github.com/Yelp/dumb-init/releases/download/v${DUMBINIT_VERSION}/dumb-init_${DUMBINIT_VERSION}_amd64 &&\
	wget -q https://github.com/Yelp/dumb-init/releases/download/v${DUMBINIT_VERSION}/sha256sums &&\
# Download Consul binary
	wget -q https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip &&\
# Download Consul integrity file
	wget -q https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_SHA256SUMS &&\
# Create links for needed tools & install dumb-init
	ln -sf /bin/busybox.static /bin/chmod &&\
	ln -sf /bin/busybox.static /bin/chown &&\
	ln -sf /bin/busybox.static /bin/grep &&\
	ln -sf /bin/busybox.static /bin/head &&\
	ln -sf /bin/busybox.static /bin/ifconfig &&\
	ln -sf /bin/busybox.static /bin/mv &&\
	ln -sf /bin/busybox.static /bin/sed &&\
	ln -sf /bin/busybox.static /bin/sleep &&\
	ln -sf /bin/busybox.static /bin/tr &&\
# Check integrity and installs dumb-init
	grep "dumb-init_${DUMBINIT_VERSION}_amd64$" sha256sums|sha256sum -c &&\
	mv dumb-init_${DUMBINIT_VERSION}_amd64 /bin/dumb-init &&\
	chmod +x /bin/* &&\
# Check integrity and installs Consul
	grep "consul_${CONSUL_VERSION}_linux_amd64.zip$" consul_${CONSUL_VERSION}_SHA256SUMS | sha256sum -c &&\
	unzip -q -o consul_${CONSUL_VERSION}_linux_amd64.zip -d /bin &&\
# Allows Consul to bind to reserved ports (for DNS)
	ssetcap 'cap_net_bind_service=+ep' /bin/consul &&\
# Add CA to system trusted store
	cat /etc/tls/ca.pem >> /etc/ssl/certs/ca-certificates.crt &&\
	touch /etc/ssl/certs/ca-consul.done &&\
# Create Consul user
	#echo "root:x:0:0:root:/dev/shm:/bin/ash" > /etc/passwd &&\
	#echo "root:x:0:root" > /etc/group &&\
	touch /etc/group &&\
	/bin/busybox.static addgroup consul &&\
	/bin/busybox.static adduser -h /tmp -H -g 'Consul user' -s /dev/null -D -G consul consul &&\
# Create Consul data directory
	mkdir /data &&\
	chown -R consul: /data &&\
	chown -R consul: /etc/consul &&\
	chmod 770 /etc/consul &&\
	chmod 660 /etc/consul/consul.json &&\
	chmod 770 /data &&\
# Cleanup
	rm -f /bin/ssetcap &&\
	rm -f consul_${CONSUL_VERSION}_* sha256sums .ash*

# On build provide your own consul dns name on the environment variable CONSUL_DNS_NAME
# and your own certificates
ONBUILD COPY consul.json /etc/consul/consul.json
ONBUILD COPY tls/ etc/tls/

# When you build on top of this image, put Consul data on a separate volume to
# avoid filesystem performance issues with Docker image layers
#VOLUME ["/data"]

USER consul
CMD ["/bin/start_consul.sh"]
