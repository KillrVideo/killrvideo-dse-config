#!/bin/bash
set -e

echo '===> DSE Configuration'

# Default addresses to use for DSE cluster if starting in Docker
dse_ip='dse'
dse_external_ip=$KILLRVIDEO_DOCKER_IP
dse_enable_ssl='false'

# Create cql_options variable to consolidate multiple options into one
# variable for easier reading
cql_options=''
# Use space variable to concatenate options
space=' '

# If an external cluster address is provided, use that
if [ ! -z "$KILLRVIDEO_DSE_EXTERNAL_IP" ]; then
  dse_ip=$KILLRVIDEO_DSE_EXTERNAL_IP
  dse_external_ip=$KILLRVIDEO_DSE_EXTERNAL_IP
fi
echo "=> Setting up KillrVideo via DSE node at: $dse_ip"

# If a request timeout is available use that.  This is useful
# in cases where a longer timeout is needed for cqlsh operations
if [ ! -z "$KILLRVIDEO_DSE_REQUEST_TIMEOUT" ]; then
  dse_request_timeout="--request-timeout=$KILLRVIDEO_DSE_REQUEST_TIMEOUT --connect-timeout=$KILLRVIDEO_DSE_REQUEST_TIMEOUT"
  cql_options="$dse_request_timeout"

  echo "=> Request timeout set at: $dse_request_timeout"
fi

# If SSL is enabled, then provide SSL info
if [ "$KILLRVIDEO_ENABLE_SSL" = 'true' ]; then
  dse_enable_ssl='true'

  # The reference to this file is provided via a volume enabled
  # on the dse-config container within docker-compose.yaml
  # in the killrvideo-docker-common repo 
  dse_ssl_certfile='/opt/killrvideo-data/cassandra.cert'
  dse_ssl='--ssl'
  cql_options="$cql_options$space$dse_ssl"

  # These 2 environment variables are needed for cqlsh to 
  # properly handle SSL
  export SSL_CERTFILE=$dse_ssl_certfile
  export SSL_VALIDATE=true
  echo "=> SSL encryption is ENABLED with CERT FILE: $dse_ssl_certfile"
fi

# Wait for port 9042 (CQL) to be ready for up to 300 seconds
echo '=> Waiting for DSE to become available'
/wait-for-it.sh -t 300 $dse_ip:9042
echo '=> DSE is available'
echo "=> If any exist, cql_options are: $cql_options"

# Default privileges
admin_user='cassandra'
admin_password='cassandra'
dse_user='cassandra'
dse_password='cassandra'

# If requested, create a new superuser to replace the default superuser
if [ "$KILLRVIDEO_CREATE_ADMIN_USER" = 'true' ]; then
  # Check if initialisation is done already
  if [ cqlsh $dse_ip 9042 -u $admin_user -p $admin_password $cql_options -e "DESCRIBE KEYSPACE kv_init_done;" 2>&1 | grep -q 'CREATE KEYSPACE kv_init_done' ]; then
    echo "The database is already initialised, exiting..."
    exit 0
  fi

  echo "=> Creating new superuser $KILLRVIDEO_ADMIN_USERNAME"
  cqlsh $dse_ip 9042 -u $admin_user -p $admin_password $cql_options -e "CREATE ROLE $KILLRVIDEO_ADMIN_USERNAME with SUPERUSER = true and LOGIN = true and PASSWORD = '$KILLRVIDEO_ADMIN_PASSWORD'"
  # Login as new superuser to delete default superuser (cassandra)
  cqlsh $dse_ip 9042 -u $KILLRVIDEO_ADMIN_USERNAME -p $KILLRVIDEO_ADMIN_PASSWORD $cql_options -e "DROP ROLE $admin_user"
fi

# Use new admin credentials for future actions
if [ ! -z "$KILLRVIDEO_ADMIN_USERNAME" ]; then
  admin_user=$KILLRVIDEO_ADMIN_USERNAME
  admin_password=$KILLRVIDEO_ADMIN_PASSWORD
fi

if cqlsh $dse_ip 9042 -u $admin_user -p $admin_password $cql_options -e "DESCRIBE KEYSPACE kv_init_done;" 2>&1 | grep -q 'CREATE KEYSPACE kv_init_done'; then
  if [ ! -z "$KILLRVIDEO_FORCE_BOOTSTRAP" ]; then
    echo '=> Forced bootstrap!'
  else 
    echo "The database is already initialised, exiting..."
    exit 0
  fi
fi

# If requested, create a new standard user
if [ "$KILLRVIDEO_CREATE_DSE_USER" = 'true' ]; then
  # Create user and grant permission to create keyspaces (generator and web will need)
  echo "=> Creating user $KILLRVIDEO_DSE_USERNAME and granting keyspace creation permissions"
  cqlsh $dse_ip 9042 -u $admin_user -p $admin_password $cql_options -e "CREATE ROLE $KILLRVIDEO_DSE_USERNAME with LOGIN = true and PASSWORD = '$KILLRVIDEO_DSE_PASSWORD'"
  echo '=> Granting keyspace creation permissions'
  cqlsh $dse_ip 9042 -u $admin_user -p $admin_password $cql_options -e "GRANT CREATE on ALL KEYSPACES to $KILLRVIDEO_DSE_USERNAME"
  cqlsh $dse_ip 9042 -u $admin_user -p $admin_password $cql_options -e "GRANT ALL PERMISSIONS on ALL SEARCH INDICES to $KILLRVIDEO_DSE_USERNAME"
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
cqlsh $dse_ip 9042 -f $keyspace_file -u $dse_user -p $dse_password $cql_options

# TODO: Complete nodesync section once documentation is available
# Once we create the keyspace enable nodesync
# Commenting this out for now until we can get the correct
# documentation needed for using nodesync over SSL
#echo '=> Enabling NodeSync for KillrVideo keyspace'
#/opt/dse/resources/cassandra/bin/nodesync -cu $dse_user -cp $dse_password -h $dse_ip --cql-ssl enable -v -k killrvideo "*"

# Create the schema if necessary
echo '=> Ensuring schema is created'
cqlsh $dse_ip 9042 -f /opt/killrvideo-data/schema.cql -k killrvideo -u $dse_user -p $dse_password $cql_options

# Create DSE Search core if necessary
echo '=> Ensuring DSE Search is configured'
# TODO: temp workaround - if search index already exists, ALTER statements will cause non-zero exit
set +e 
cqlsh $dse_ip 9042 -f /opt/killrvideo-data/videos_search.cql -k killrvideo -u $dse_user -p $dse_password $cql_options
# TODO: remove workaround
set -e

# Wait for port 8182 (Gremlin) to be ready for up to 120 seconds
echo '=> Waiting for DSE Graph to become available'
/wait-for-it.sh -t 120 $dse_ip:8182
echo '=> DSE Graph is available'

# Update the gremlin-console remote.yaml file to set the remote hosts, username, and password
# This is required because the "dse gremlin-console" command does not accept username/password via command line
echo '=> Setting up remote.yaml for gremlin-console'
sed -i "s/.*hosts:.*/hosts: [$dse_ip]/;s/.*username:.*/username: $dse_user/;s/.*password:.*/password: $dse_password/;s|enableSsl:.*|enableSsl: $dse_enable_ssl, trustCertChainFile: $dse_ssl_certfile,|;" /opt/dse/resources/graph/gremlin-console/conf/remote.yaml

# Create the graph if necessary
echo '=> Ensuring graph is created'
graph_file='/opt/killrvideo-data/killrvideo_video_recommendations_schema.groovy'
if [ ! -z "$KILLRVIDEO_GRAPH_REPLICATION" ]; then
  sed -i "s/{.*}/$KILLRVIDEO_GRAPH_REPLICATION/;" $graph_file
fi
dse gremlin-console -e $graph_file

echo '=> Configuration of DSE users and schema complete'

# Don't bootstrap next time we start
cqlsh $dse_ip 9042 -u $dse_user -p $dse_password $cql_options -e "CREATE KEYSPACE IF NOT EXISTS kv_init_done WITH REPLICATION = {'class': 'SimpleStrategy', 'replication_factor': 1};"
