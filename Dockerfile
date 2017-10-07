FROM alpine:3.6

MAINTAINER Miguel Terron <miguel.a.terron@gmail.com>

ARG BUILD_DATE
ARG VCS_REF

# Set environment variables
ENV PATH=$PATH:/native/usr/bin:/native/usr/sbin:/native/sbin:/native/bin:/bin \
	CONSUL_VERSION=0.9.3

LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.vcs-url="https://github.com/mterron/consul.git" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.schema-version="1.0.0-rc.1" \
      org.label-schema.version=$CONSUL_VERSION \
      org.label-schema.description="Alpine based Consul image"

RUN	apk -q --no-cache upgrade &&\
	apk -q add --no-cache ca-certificates jq gnupg libcap su-exec tini tzdata wget &&\
	gpg --keyserver pgp.mit.edu --recv-keys 91A6E7F85D05C65630BEF18951852D87348FFC4C &&\
	echo 'Download Consul binary' &&\
	wget -nv --progress=bar:force --show-progress https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip &&\
	echo 'Download Consul integrity file' &&\
	wget -nv --progress=bar:force --show-progress https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_SHA256SUMS &&\
	wget -nv --progress=bar:force --show-progress https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_SHA256SUMS.sig &&\
# Check integrity and installs Consul
	gpg --batch --verify consul_${CONSUL_VERSION}_SHA256SUMS.sig consul_${CONSUL_VERSION}_SHA256SUMS &&\
	grep "consul_${CONSUL_VERSION}_linux_amd64.zip$" consul_${CONSUL_VERSION}_SHA256SUMS | sha256sum -c &&\
	unzip -q -o consul_${CONSUL_VERSION}_linux_amd64.zip -d /bin &&\
# Create Consul user
	adduser -H -h /tmp -D -g 'Consul user' -s /dev/null consul &&\
	adduser root consul &&\
# Cleanup
	apk -q del --purge ca-certificates gnupg wget &&\
	rm -rf consul_${CONSUL_VERSION}_* .ash* /root/.gnupg

# Copy binaries. bin directory contains startup script
COPY bin/* /usr/local/bin/

# Copy /etc (Consul config and certificates)
COPY etc/ /etc

RUN	mkdir -m 770 /data &&\
	chmod 770 /etc/consul &&\
	chmod 660 /etc/consul/consul.json &&\
# Fix permissions
	chown -R consul: /data &&\
	chown -R consul: /etc/consul &&\
# Add CA to system trusted store
	mkdir -p /etc/ssl/certs/ &&\
	cat /etc/tls/ca.pem >> /etc/ssl/certs/ca-certificates.crt &&\
	touch /etc/ssl/certs/ca-consul.done


# On build provide your own consul dns name on the environment variable CONSUL_DNS_NAME
# and your own certificates
ONBUILD COPY consul.json /etc/consul/consul.json
ONBUILD COPY tls/ etc/tls/
# Fix file permissions
ONBUILD RUN chown -R consul: /etc/consul &&\
			chmod 770 /etc/consul &&\
			chmod 660 /etc/consul/consul.json &&\
# Add CA to system trusted store
			cat /etc/tls/ca.pem >> /etc/ssl/certs/ca-certificates.crt &&\
			touch /etc/ssl/certs/ca-consul.done


ENTRYPOINT ["tini", "-g", "--"]
CMD ["start_consul.sh"]

# Serf LAN and WAN (WAN is used only by Consul servers) are used for gossip between
# Consul agents. LAN is used within the datacenter and WAN between Consul servers
# in all datacenters.
# HTTPS, and DNS (both TCP and UDP) are the primary interfaces that applications
# use to interact with Consul.
EXPOSE 8301 8301/udp 8302 8302/udp 8501 53 53/udp 8600 8600/udp
