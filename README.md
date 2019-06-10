# Consul production ready container image
[![License ISC](https://img.shields.io/badge/license-ISC-blue.svg)](https://raw.githubusercontent.com/mterron/consul/master/LICENSE) [![](https://images.microbadger.com/badges/image/mterron/consul.svg)](https://microbadger.com/images/mterron/consul) [![](https://images.microbadger.com/badges/commit/mterron/consul.svg)](https://microbadger.com/images/mterron/consul)

[Consul](http://www.consul.io/) in Docker, designed for availability and durability.


## Start a trusted Consul raft

1. [Clone](https://github.com/mterron/consul) or [download](https://github.com/mterron/consul/archive/master.zip) this repo
2. Import the example client certificate (one of `client_certificate.p12`, `client_certificate.pem`, etc). This image requires client validation, an example certificate is provided ***but you should generate your own***. The password for the p12 file is "client". Also provided is a .pem and .key files for the same certificate. 
3. `cd composition` into the cloned or downloaded directory
4. run `./start.sh`
5. A browser with the Consul UI will open (on Mac OS X) or browse to `https://DOCKER_IP:BOOTSTRAP_UI_PORT` as shown on your screen.

## How it works

This demo first starts up a bootstrap node that starts the raft but expects 2 additional nodes before the raft is healthy. Once this node is up and its IP address is obtained, the rest of the nodes are started and joined to the bootstrap IP address (the value is passed in the `CONSUL_BOOTSTRAP_HOST` environment variable).

If a raft instance fails, the data is preserved among the other instances and the overall availability of the service is preserved because any single instance can authoritatively answer for all instances. Applications that depend on the Consul service should re-try failed requests until they get a response.

Any new raft instances need to be started with a bootstrap IP address, but after the initial cluster is created, the `CONSUL_BOOTSTRAP_HOST` IP address can be any host currently in the raft. This means there is no dependency on the first node after the cluster has been formed. After the raft has been initialised, nodes can join `consul.service.consul` if they are using Consul as DNS or have redirected the .consul domain to Consul.

# Credit where it's due

This project builds on the fine examples set by the [AutoPilot](http://autopilotpattern.io) pattern guys. It also, obviously, wouldn't be possible without the outstanding work of the [Hashicorp team](https://hashicorp.com) that made [Consul](https://consul.io).
