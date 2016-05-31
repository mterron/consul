# Consul autopilot pattern
[![License MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://raw.githubusercontent.com/mterron/consul-autopilot/master/LICENSE)

[Consul](http://www.consul.io/) in Docker, designed for availability and durability.


## Start a trusted Consul raft

1. [Clone](https://github.com/mterron/consul-autopilot) or [download](https://github.com/mterron/consul-autopilot/archive/master.zip) this repo
2. `cd composition` into the cloned or downloaded directory
3. docker-compose up -d && docker-compose scale consul=3
4. Connect to the Consul UI pointing your broser to the IP of any of the Consul containers.

## How it works

This demo first starts up a bootstrap node that starts the raft but expects 2 additional nodes before the raft is healthy. Once this node is up and its IP address is obtained, the rest of the nodes are started and joined to the bootstrap IP address (the value is passed in the `BOOTSTRAP_HOST` environment variable).

If a raft instance fails, the data is preserved among the other instances and the overall availability of the service is preserved because any single instance can authoritatively answer for all instances. Applications that depend on the Consul service should re-try failed requests until they get a response.

Any new raft instances need to be started with a bootstrap IP address, but after the initial cluster is created, the `BOOTSTRAP_HOST` IP address can be any host currently in the raft. This means there is no dependency on the first node after the cluster has been formed. After the raft, nodes can join `consul.service.consul`

# Credit where it's due

This project builds on the fine examples set by the [AutoPilot](http://autopilotpattern.io) pattern guys. It also, obviously, wouldn't be possible without the outstanding work of the [Hashicorp team](https://hashicorp.com) that made [Consul](https://consul.io).
