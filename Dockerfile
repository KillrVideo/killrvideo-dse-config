FROM datastax/dse-server:6.7.0

# Copy schema files into /opt/killrvideo-data
COPY [ "lib/killrvideo-data/graph/killrvideo_video_recommendations_schema.groovy", "lib/killrvideo-data/schema.cql", "lib/killrvideo-data/search/*", "keyspace.cql", "/opt/killrvideo-data/" ]

# Copy bootstrap script(s) and make executable
COPY [ "bootstrap.sh", "lib/wait-for-it/wait-for-it.sh", "/" ]

# Make sure curl command is available for registering DSE ports with etcd
USER root
RUN set -x \
  && apt-get update -qq && apt-get install -y curl
#  && apt-get install -y sudo

# Set the entrypoint to the bootstrap script
ENTRYPOINT [ "/bootstrap.sh" ]
