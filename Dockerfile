FROM alpine:latest

LABEL maintainer="Miguel Terron <miguel.a.terron@gmail.com>"

ARG BUILD_DATE
ARG VCS_REF
ARG CONSUL_VERSION=1.2.1
ARG HASHICORP_PGP_KEY=51852D87348FFC4C

LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.vcs-url="https://github.com/mterron/consul.git" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.schema-version="1.0.0-rc.1" \
      org.label-schema.version=$CONSUL_VERSION \
      org.label-schema.description="Alpine based Consul image"

RUN	apk -q --no-cache add binutils ca-certificates curl gnupg jq libcap su-exec tini tzdata wget &&\
	gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$HASHICORP_PGP_KEY" &&\
	echo 'Download Consul binary' &&\
	wget -nv --progress=bar:force --show-progress https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip &&\
	echo 'Download Consul integrity file' &&\
	wget -nv --progress=bar:force --show-progress https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_SHA256SUMS &&\
	wget -nv --progress=bar:force --show-progress https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_SHA256SUMS.sig &&\
# Check integrity and installs Consul
	gpg --batch --verify consul_${CONSUL_VERSION}_SHA256SUMS.sig consul_${CONSUL_VERSION}_SHA256SUMS &&\
	grep "consul_${CONSUL_VERSION}_linux_amd64.zip$" consul_${CONSUL_VERSION}_SHA256SUMS | sha256sum -c &&\
	unzip -q -o consul_${CONSUL_VERSION}_linux_amd64.zip -d /usr/local/bin &&\
	strip --strip-debug /usr/local/bin/consul &&\
# Create Consul user
	addgroup -S consul &&\
	adduser -H -h /tmp -D -S -G consul -g 'Consul user' -s /dev/null consul &&\
# Assign a linux capability to the Consul binary that allows it to bind to low ports in case it's needed
	setcap 'cap_net_bind_service=+ep' /usr/local/bin/consul &&\
	adduser root consul &&\
# Cleanup
	apk -q --no-cache del --purge binutils ca-certificates gnupg wget &&\
	rm -rf consul_${CONSUL_VERSION}_* .ash* /root/.gnupg

# Copy binaries. bin directory contains startup script
COPY bin/* /usr/local/bin/

# Copy Consul config
COPY --chown=consul:consul consul.json /etc/consul/
# Copy certificates
COPY tls/* /etc/tls/

# Add CA to system trusted store
RUN	cat /etc/tls/ca.pem >> /etc/ssl/certs/ca-certificates.crt

# On build provide your own consul dns name on the environment variable CONSUL_DNS_NAME
# and your own certificates matching that domain
ONBUILD COPY --chown=consul:consul consul.json /etc/consul/consul.json
# Copy certificates
ONBUILD COPY tls/* /etc/tls/
# Add CA to system trusted store
ONBUILD RUN cat /etc/tls/ca.pem >> /etc/ssl/certs/ca-certificates.crt

ENTRYPOINT ["tini", "-g", "--"]
CMD ["start_consul"]

HEALTHCHECK --start-period=300s CMD consul operator raft list-peers | grep -q leader

# Serf LAN and WAN (WAN is used only by Consul servers) are used for gossip between
# Consul agents. LAN is used within the datacenter and WAN between Consul servers
# in all datacenters.
# HTTPS, and DNS (both TCP and UDP) are the primary interfaces that applications
# use to interact with Consul.
EXPOSE 8301 8301/udp 8302 8302/udp 8501 53 53/udp 8600 8600/udp

STOPSIGNAL SIGINT

COPY Dockerfile /etc/
