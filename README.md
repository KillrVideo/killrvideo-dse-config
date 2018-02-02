# KillrVideo DSE Docker

[![Build Status](https://travis-ci.org/KillrVideo/killrvideo-dse-config.svg?branch=master)](https://travis-ci.org/KillrVideo/killrvideo-dse-config)

Docker container to configure a [DataStax Enterprise][dse] cluster for use with KillrVideo,
including single and multi-node clusters, with options as described below. Contains startup 
scripts to bootstrap the CQL and DSE Search resources needed by the [KillrVideo][killrvideo] 
application. Based on the official [DSE image][dse-docker] from the Docker Store.

## Configuration Options

This container supports several different options for configuration:

### DSE Node location (required)
The `KILLRVIDEO_DSE_IP` environment variable must be set in order to provide the location of at
least one node in the cluster that the container will connect to in order to perform configuration.

- For a configuration in which DSE will be run in a Docker container along with this configuration
container and other containers in the KillrVideo ecosystem, `KILLRVIDEO_DSE_IP` should be set to the
name given for the container image, i.e. "dse". Docker will resolve this name to the correct IP.
- For a configuration in which DSE is running separately from the Docker configuration, 
`KILLRVIDEO_DSE_IP` should be set to the resolvable address of a node in the externally managed 
cluster.

### Single-node vs multi-node clusters 
KillrVideo may require keyspaces to be created with different replication strategies depending
on where it is deployed to use a single- or multi-node DSE cluster (i.e. for development vs. 
production deployments). 

- If the `KILLRVIDEO_MULTI_NODE_CLUSTER` environment variable is set to true, the replication
strategy for KillrVideo related keyspaces will be set to X. Otherwise, keyspaces will have  
be set to use the <code>SimpleStrategy</code> with replication factor of 1.
### Enabling authentication and authorization
This container can optionally create administrative and/or standard (application) roles:

- Administrative role - if the environment variable `KILLRVIDEO_CREATE_ADMIN_USER` is set to true, 
an administrative role with the credentials specfied by the `KILLRVIDEO_ADMIN_USERNAME` and
`KILLRVIDEO_ADMIN_PASSWORD` environment variables will be created, and the default admin user 
(cassandra/cassandra) will be removed. This is particularly useful for desktop deployments.
- Application role - if the environment variable `KILLRVIDEO_CREATE_DSE_USER` is set to true, 
  a role with the credentials specfied by the `KILLRVIDEO_DSE_USERNAME` and
  `KILLRVIDEO_DSE_PASSWORD` environment variables will be created. This role will be granted
  permissions required by the KillrVideo application. The same username/password environment
  variables be provided to clients (containers) in the KillrVideo ecosystem 
  such as the web application and test data generator in order for them to authenticate
  to DSE.

For additional information on running DSE nodes within Docker as part of a KillrVideo deployment,
please see the Docker page

## Builds and Releases

The `./build` folder contains a number of scripts to help with builds and releases. Continuous
integration builds are done by Travis and any commits that are tagged will also automatically
be released to the [Docker Hub][docker-hub] page. We try to follow semantic versioning,
however the version numbering is not related to what version of DSE we're using. For example,
version `1.0.0` uses DSE version `5.1.5`.

[dse]: http://www.datastax.com/products/datastax-enterprise
[killrvideo]: https://killrvideo.github.io/
[dse-docker]: https://store.docker.com/images/datastax
[docker-hub]: https://hub.docker.com/r/killrvideo/killrvideo-dse/
