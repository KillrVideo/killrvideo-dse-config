#!/bin/bash
set -e

# See if we've already completed bootstrapping
if [ ! -f killrvideo_bootstrapped ]; then

  # Default addresses to use for DSE cluster if starting in Docker
  dse_ip='dse'
  dse_external_ip=$KILLRVIDEO_DOCKER_IP

  # If an external cluster address is provided, use that
  if [ ! -z "$KILLRVIDEO_DSE_EXTERNAL_IP" ]; then
    dse_ip=$KILLRVIDEO_DSE_EXTERNAL_IP
    dse_external_ip=$KILLRVIDEO_DSE_EXTERNAL_IP
  fi
  echo "Setting up KillrVideo via DSE node at $dse_ip"

  # Wait for port 9042 (CQL) to be ready for up to 240 seconds
  echo '=> Waiting for DSE to become available'
  /wait-for-it.sh -t 120 $dse_ip:9042
  echo '=> DSE is available'

  # Default privileges
  admin_user='cassandra'
  admin_password='cassandra'
  dse_user='cassandra'
  dse_password='cassandra'

  # If requested, create a new superuser to replace the default superuser
  if [ "$KILLRVIDEO_CREATE_ADMIN_USER" = 'true' ]; then
    echo "=> Creating new superuser $KILLRVIDEO_ADMIN_USERNAME"
    cqlsh $dse_ip 9042 -u $admin_user -p $admin_password -e "CREATE ROLE $KILLRVIDEO_ADMIN_USERNAME with SUPERUSER = true and LOGIN = true and PASSWORD = '$KILLRVIDEO_ADMIN_PASSWORD'"
    # Login as new superuser to delete default superuser (cassandra)
    cqlsh $dse_ip 9042 -u $KILLRVIDEO_ADMIN_USERNAME -p $KILLRVIDEO_ADMIN_PASSWORD -e "DROP ROLE $admin_user"
  fi

  # Use new admin credentials for future actions
  if [ ! -z "$KILLRVIDEO_ADMIN_USERNAME" ]; then
    admin_user=$KILLRVIDEO_ADMIN_USERNAME
    admin_password=$KILLRVIDEO_ADMIN_PASSWORD
  fi

  # If requested, create a new standard user
  if [ "$KILLRVIDEO_CREATE_DSE_USER" = 'true' ]; then
    # Create user and grant permission to create keyspaces (generator and web will need)
    echo "=> Creating user $KILLRVIDEO_DSE_USERNAME and granting keyspace creation permissions"
    cqlsh $dse_ip 9042 -u $admin_user -p $admin_password -e "CREATE ROLE $KILLRVIDEO_DSE_USERNAME with LOGIN = true and PASSWORD = '$KILLRVIDEO_DSE_PASSWORD'"
    echo '=> Granting keyspace creation permissions'
    cqlsh $dse_ip 9042 -u $admin_user -p $admin_password -e "GRANT CREATE on ALL KEYSPACES to $KILLRVIDEO_DSE_USERNAME"
    cqlsh $dse_ip 9042 -u $admin_user -p $admin_password -e "GRANT ALL PERMISSIONS on ALL SEARCH INDICES to $KILLRVIDEO_DSE_USERNAME"
  fi

  # Use the provided username/password for subsequent non-admin operations
  if [ ! -z "$KILLRVIDEO_DSE_USERNAME" ]; then
    dse_user=$KILLRVIDEO_DSE_USERNAME
    dse_password=$KILLRVIDEO_DSE_PASSWORD
  fi

  # Create the keyspace if necessary
  echo '=> Ensuring keyspace is created'
  keyspace_file='/opt/killrvideo-data/keyspace.cql'
  if [ ! -z "$KILLRVIDEO_CASSANDRA_REPLICATION" ]; then
    # TODO: check for valid replication format? https://stackoverflow.com/questions/21112707/check-if-a-string-matches-a-regex-in-bash-script
    sed -i "s/{.*}/$KILLRVIDEO_CASSANDRA_REPLICATION/;" $keyspace_file
  fi
  cqlsh $dse_ip 9042 -f $keyspace_file -u $dse_user -p $dse_password

  # Create the schema if necessary
  echo '=> Ensuring schema is created'
  cqlsh $dse_ip 9042 -f /opt/killrvideo-data/schema.cql -k killrvideo -u $dse_user -p $dse_password

  # Create DSE Search core if necessary
  echo '=> Ensuring DSE Search is configured'
  cqlsh $dse_ip 9042 -f /opt/killrvideo-data/videos_search.cql -k killrvideo -u $dse_user -p $dse_password

  # Wait for port 8182 (Gremlin) to be ready for up to 120 seconds
  echo '=> Waiting for DSE Graph to become available'
  /wait-for-it.sh -t 120 $dse_ip:8182
  echo '=> DSE Graph is available'

  # Update the gremlin-console remote.yaml file to set the remote hosts, username, and password
  # This is required because the "dse gremlin-console" command does not accept username/password via command line
  echo '=> Setting up remote.yaml for gremlin-console'
  sed -i "s/.*hosts:.*/hosts: [$dse_ip]/;s/.*username:.*/username: $dse_user/;s/.*password:.*/password: $dse_password/;" /opt/dse/resources/graph/gremlin-console/conf/remote.yaml

  # Create the graph if necessary
  echo '=> Ensuring graph is created'
  graph_file='/opt/killrvideo-data/killrvideo_video_recommendations_schema.groovy'
  if [ ! -z "$KILLRVIDEO_GRAPH_REPLICATION" ]; then
    sed -i "s/{.*}/$KILLRVIDEO_GRAPH_REPLICATION/;" $graph_file
  fi
  dse gremlin-console -e $graph_file

  # Register services in ETCD once all the schema are configured, using an IP that will be accessible
  # internally and externally to the Docker environment
  hostname="$(hostname)"

  echo '=> Registering DSE DB (Cassandra) cluster in ETCD'
  curl "http://etcd:2379/v2/keys/killrvideo/services/cassandra/$hostname" -XPUT -d value="$dse_external_ip:9042"

  echo '=> Registering DSE Search in ETCD'
  curl "http://etcd:2379/v2/keys/killrvideo/services/dse-search/$hostname" -XPUT -d value="$dse_external_ip:8983"

  echo '=> Registering DSE Graph in ETCD'
  curl "http://etcd:2379/v2/keys/killrvideo/services/gremlin/$hostname" -XPUT -d value="$dse_external_ip:8182"

  # Don't bootstrap next time we start
  echo '=> Configuration of DSE users and schema complete'
  touch killrvideo_bootstrapped
fi
