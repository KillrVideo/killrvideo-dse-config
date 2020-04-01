# KillrVideo DSE Docker

[![Build Status](https://travis-ci.org/KillrVideo/killrvideo-dse-config.svg?branch=master)](https://travis-ci.org/KillrVideo/killrvideo-dse-config)

Docker container to configure a [DataStax Enterprise][dse] cluster for use with KillrVideo,
including single and multi-node clusters, with options as described below. Contains startup 
scripts to bootstrap the CQL and DSE Search resources needed by the [KillrVideo][killrvideo] 
application. Based on the official [DSE image][dse-docker] from the Docker Store.

## Configuration Options

This container supports several different options for configuration:

### DSE node location
By default, this container assumes that DataStax Enterprise is being started in a Docker container
as part of a `docker-compose` configuration.

If you instead wish to deploy KillrVideo with an existing cluster, you can override this 
behavior by setting the value of the `KILLRVIDEO_DSE_CONTACT_POINTS` environment variable to the location 
of a node in the external cluster. (Don't forget to modify `docker-compose` files so that
you don't continue to run DSE in Docker. See the [KillrVideo Docker documentation page][docker-doc] 
for more information.) 

### Configuring replication strategies 
KillrVideo may require keyspaces to be created with different replication strategies depending
on where it is deployed to use a single- or multi-node DSE cluster (i.e. for development vs. 
production deployments). 

- By default, this container will create KillrVideo keyspaces for DSE Database (Cassandra) 
and DSE Graph using the `SimpleStrategy` with a replication factor of 1.
- You can override the replication factor that will be used for the primary application Cassandra
tables by setting the `KILLRVIDEO_CASSANDRA_REPLICATION` environment variable. Here's an example
of how to set this variable in an `.env` file you use with `docker-compose`:
```
KILLRVIDEO_CASSANDRA_REPLICATION={'class' : 'NetworkTopologyStrategy', 'us-west-2-graph' : 3}
```
- Similarly, you can override the replication factor that will be used for the graph on which our 
recommendation engine is implemented by setting the `KILLRVIDEO_GRAPH_REPLICATION` environment variable. 

### Enabling authentication and authorization
This container can optionally use administrative and/or standard (application) roles and even create the roles on 
request:

- Using an administrator role - if the environment variables `KILLRVIDEO_ADMIN_USERNAME` and
`KILLRVIDEO_ADMIN_PASSWORD` are set, the provided values will be used as the credentials for configuration steps 
requiring administrative privileges
- Creating an administrator role - if the environment variable `KILLRVIDEO_CREATE_ADMIN_USER` is set to true, 
an administrative role with the credentials specfied by the `KILLRVIDEO_ADMIN_USERNAME` and
`KILLRVIDEO_ADMIN_PASSWORD` environment variables will be created, and the default admin user 
(cassandra/cassandra) will be removed. This is particularly useful for desktop deployments.
- Using an application role - if the environment variables `KILLRVIDEO_DSE_USERNAME` and
`KILLRVIDEO_DSE_PASSWORD` are set, the provided values will be used as the credentials for configuration steps 
that don't require administrative privileges
- Creating an application role - if the environment variable `KILLRVIDEO_CREATE_DSE_USER` is set to true, 
a role with the credentials specfied by the `KILLRVIDEO_DSE_USERNAME` and `KILLRVIDEO_DSE_PASSWORD` environment 
variables will be created. This role will be granted permissions required by the KillrVideo application. The same 
username/password environment variables be provided to clients (containers) in the KillrVideo ecosystem such as the 
web application and test data generator in order for them to authenticate to DSE.

For additional information on running DSE nodes within Docker as part of a KillrVideo deployment,
please see the [KillrVideo Docker documentation page][docker-doc].

## Builds and Releases

Continuous integration builds are done by Travis and any commits that are tagged will also automatically
be released to the [Docker Hub][docker-hub] page. We try to follow semantic versioning,
however the version numbering is not related to what version of DSE we're using. For example,
version `1.0.0` uses DSE version `5.1.5`.

[dse]: http://www.datastax.com/products/datastax-enterprise
[killrvideo]: https://killrvideo.github.io/
[dse-docker]: https://store.docker.com/images/datastax
[docker-hub]: https://hub.docker.com/r/killrvideo/killrvideo-dse/
[docker-doc]: https://killrvideo.github.io/docs/guides/docker/