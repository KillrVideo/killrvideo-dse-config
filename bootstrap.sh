#!/bin/bash
set -e

# See if we've already completed bootstrapping
if [ ! -f killrvideo_bootstrapped ]; then
  echo "Setting up KillrVideo via DSE node at $KILLRVIDEO_DSE_IP"

  # Wait for port 9042 (CQL) to be ready for up to 240 seconds
  echo '=> Waiting for DSE to become available'
  /wait-for-it.sh -t 120 $KILLRVIDEO_DSE_IP:9042
  echo '=> DSE is available'

  # Default administrator privileges
  admin_user='cassandra'
  admin_password='cassandra'

  # If requested, create a new superuser to replace the default superuser
  if [ "$KILLRVIDEO_CREATE_ADMIN_USER" = 'true' ]; then
    echo "=> Creating new superuser $KILLRVIDEO_ADMIN_USERNAME"
    cqlsh $KILLRVIDEO_DSE_IP 9042 -u $admin_user -p $admin_password -e "CREATE ROLE $KILLRVIDEO_ADMIN_USERNAME with SUPERUSER = true and LOGIN = true and PASSWORD = '$KILLRVIDEO_ADMIN_PASSWORD'"
    # Login as new superuser to delete default superuser (cassandra)
    cqlsh $KILLRVIDEO_DSE_IP 9042 -u $KILLRVIDEO_ADMIN_USERNAME -p $KILLRVIDEO_ADMIN_PASSWORD -e "DROP ROLE $admin_user"
    # Use new admin credentials for future actions
    admin_user=$KILLRVIDEO_ADMIN_USERNAME
    admin_password=$KILLRVIDEO_ADMIN_PASSWORD
  fi

  # If requested, create a new standard user
  if [ "$KILLRVIDEO_CREATE_DSE_USER" = 'true' ]; then
    # Create user and grant permission to create keyspaces (generator and web will need)
    echo "=> Creating user $KILLRVIDEO_DSE_USERNAME and granting keyspace creation permissions"
    cqlsh $KILLRVIDEO_DSE_IP 9042 -u $admin_user -p $admin_password -e "CREATE ROLE $KILLRVIDEO_DSE_USERNAME with LOGIN = true and PASSWORD = '$KILLRVIDEO_DSE_PASSWORD'"
    echo '=> Granting keyspace creation permissions'
    cqlsh $KILLRVIDEO_DSE_IP 9042 -u $admin_user -p $admin_password -e "GRANT CREATE on ALL KEYSPACES to $KILLRVIDEO_DSE_USERNAME"
    cqlsh $KILLRVIDEO_DSE_IP 9042 -u $admin_user -p $admin_password -e "GRANT ALL PERMISSIONS on ALL SEARCH INDICES to $KILLRVIDEO_DSE_USERNAME"
  fi

  # Create the keyspace if necessary
  echo '=> Ensuring keyspace is created'
  keyspace_file='/opt/killrvideo-data/keyspace.cql'
  if [ ! -z "$KILLRVIDEO_CASSANDRA_REPLICATION" ]; then
    sed -i "s/{.*}:[$KILLRVIDEO_CASSANDRA_REPLICATION]/;" $keyspace_file
  fi
  cqlsh $KILLRVIDEO_DSE_IP 9042 -f $keyspace_file -u $KILLRVIDEO_DSE_USERNAME -p $KILLRVIDEO_DSE_PASSWORD

  # Create the schema if necessary
  echo '=> Ensuring schema is created'
  cqlsh $KILLRVIDEO_DSE_IP 9042 -f /opt/killrvideo-data/schema.cql -k killrvideo -u $KILLRVIDEO_DSE_USERNAME -p $KILLRVIDEO_DSE_PASSWORD

  # Create DSE Search core if necessary
  echo '=> Ensuring DSE Search is configured'
  search_action='reload'
    
  # Check for config (dsetool will return a message like 'No resource solrconfig.xml found for core XXX' if not created yet)
  cfg="$(dsetool -h $KILLRVIDEO_DSE_IP get_core_config killrvideo.videos -l $admin_user -p $admin_password)"
  if [[ $cfg == "No resource"* ]]; then
    search_action='create'
  fi

  # Create or reload core
  if [ "$search_action" = 'create' ]; then
    echo '=> Creating search core'
    dsetool -h $KILLRVIDEO_DSE_IP create_core killrvideo.videos schema=/opt/killrvideo-data/videos.schema.xml solrconfig=/opt/killrvideo-data/videos.solrconfig.xml -l $admin_user -p $admin_password
  else
    echo '=> Reloading search core'
    dsetool -h $KILLRVIDEO_DSE_IP reload_core killrvideo.videos schema=/opt/killrvideo-data/videos.schema.xml solrconfig=/opt/killrvideo-data/videos.solrconfig.xml -l $admin_user -p $admin_password
  fi

  # Wait for port 8182 (Gremlin) to be ready for up to 120 seconds
  echo '=> Waiting for DSE Graph to become available'
  /wait-for-it.sh -t 120 $KILLRVIDEO_DSE_IP:8182
  echo '=> DSE Graph is available'

  # Update the gremlin-console remote.yaml file to set the remote hosts, username, and password
  # This is required because the "dse gremlin-console" command does not accept username/password via command line
  echo '=> Setting up remote.yaml for gremlin-console'
  sed -i "s/.*hosts:.*/hosts: [$KILLRVIDEO_DSE_IP]/;s/.*username:.*/username: $KILLRVIDEO_DSE_USERNAME/;s/.*password:.*/password: $KILLRVIDEO_DSE_PASSWORD/;" /opt/dse/resources/graph/gremlin-console/conf/remote.yaml

  # Create the graph if necessary
  echo '=> Ensuring graph is created'
  graph_file='/opt/killrvideo-data/killrvideo_video_recommendations_schema.groovy'
  if [ ! -z "$KILLRVIDEO_GRAPH_REPLICATION" ]; then
    sed -i "s/{.*}:[$KILLRVIDEO_GRAPH_REPLICATION]/;" $graph_file
  fi
  dse gremlin-console -e $graph_file

  # Don't bootstrap next time we start
  echo '=> Configuration of DSE users and schema complete'
  touch killrvideo_bootstrapped
fi

hostname="$(hostname)"

echo '=> Registering DSE DB (Cassandra) cluster in ETCD'
curl "http://etcd:2379/v2/keys/killrvideo/services/cassandra/$hostname" -XPUT -d value="$KILLRVIDEO_DOCKER_IP:9042"

echo '=> Registering DSE Search in ETCD'
curl "http://etcd:2379/v2/keys/killrvideo/services/dse-search/$hostname" -XPUT -d value="$KILLRVIDEO_DOCKER_IP:8983"

echo '=> Registering DSE Graph in ETCD'
curl "http://etcd:2379/v2/keys/killrvideo/services/gremlin/$hostname" -XPUT -d value="$KILLRVIDEO_DOCKER_IP:8182"

