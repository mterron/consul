FROM alpine:3.6
MAINTAINER Miguel Terron <miguel.a.terron@gmail.com>

# Set environment variables
ENV PATH=$PATH:/native/usr/bin:/native/usr/sbin:/native/sbin:/native/bin:/bin \
	CONSUL_VERSION=0.8.5

RUN	apk add --no-cache ca-certificates curl jq libcap su-exec tini tzdata &&\
	chmod +x /bin/* &&\
	echo 'Download Consul binary' &&\
	curl -L# -oconsul_${CONSUL_VERSION}_linux_amd64.zip https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip &&\
	echo 'Download Consul integrity file' &&\
	curl -L# -oconsul_${CONSUL_VERSION}_SHA256SUMS https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_SHA256SUMS &&\
# Check integrity and installs Consul
	grep "consul_${CONSUL_VERSION}_linux_amd64.zip$" consul_${CONSUL_VERSION}_SHA256SUMS | sha256sum -c &&\
	unzip -q -o consul_${CONSUL_VERSION}_linux_amd64.zip -d /bin &&\
# Create Consul user
	adduser -H -h /tmp -D -g 'Consul user' -s /dev/null consul &&\
	adduser root consul &&\
# Create Consul data directory
	mkdir /data &&\
	chown -R consul: /data &&\
	chmod 770 /data &&\
# Cleanup
	rm -f consul_${CONSUL_VERSION}_* .ash*

# Copy binaries. bin directory contains startup script
COPY bin/* /usr/local/bin/

# Copy /etc (Consul config and certificates)
COPY etc/ /etc

RUN	chown -R consul: /etc/consul &&\
	chmod 770 /etc/consul &&\
	chmod 660 /etc/consul/consul.json &&\
# Add CA to system trusted store
	cat /etc/tls/ca.pem >> /etc/ssl/certs/ca-certificates.crt &&\
	touch /etc/ssl/certs/ca-consul.done


# On build provide your own consul dns name on the environment variable CONSUL_DNS_NAME
# and your own certificates
# When building on top of this image, you want to run 'consul validate /etc/consul/consul.json'
# to validate your Consul configuration file.
ONBUILD COPY consul.json /etc/consul/consul.json
ONBUILD COPY tls/ etc/tls/
# Fix file permissions
ONBUILD RUN chown -R consul: /etc/consul &&\
			chmod 770 /etc/consul &&\
			chmod 660 /etc/consul/consul.json &&\
# Add CA to system trusted store
			cat /etc/tls/ca.pem >> /etc/ssl/certs/ca-certificates.crt &&\
			touch /etc/ssl/certs/ca-consul.done


# When you build on top of this image, put Consul data on a separate volume to
# avoid filesystem performance issues with Docker image layers
#VOLUME ["/data"]

#USER consul

ENTRYPOINT ["tini", "-g", "--"]
CMD ["start_consul.sh"]

# Serf LAN and WAN (WAN is used only by Consul servers) are used for gossip between
# Consul agents. LAN is used within the datacenter and WAN between Consul servers
# in all datacenters.
# HTTPS, and DNS (both TCP and UDP) are the primary interfaces that applications
# use to interact with Consul.
EXPOSE 8301 8301/udp 8302 8302/udp 8501 53 53/udp 8600 8600/udp
