FROM datastax/dse-server:6.7.0

# Copy required files
COPY [ "lib/killrvideo-data/graph/killrvideo_video_recommendations_schema.groovy", "lib/killrvideo-data/schema.cql", "lib/killrvideo-data/search/*", "keyspace.cql", "/opt/killrvideo-data/" ]
COPY [ "bootstrap.sh", "lib/wait-for-it/wait-for-it.sh", "/" ]

# Set the entrypoint to the bootstrap script
ENTRYPOINT [ "/bootstrap.sh" ]
