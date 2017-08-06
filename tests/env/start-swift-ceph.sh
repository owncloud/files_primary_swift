#!/usr/bin/env bash
#
# ownCloud
#
# This script start a docker container to test the files_external tests
# against. It will also change the files_external config to use the docker
# container as testing environment. This is reverted in the stop step.W
#
# Set environment variable DEBUG to print config file
#
# @author Morris Jobke
# @author Robin McCorkell
# @author Jörn Friedrich Dreyer
# @author Thomas Müller
# @author Piotr Mrowczynski
# @copyright 2015-2017 ownCloud GmbH

if ! command -v docker >/dev/null 2>&1; then
    echo "No docker executable found - skipped docker setup"
    exit 0;
fi

echo "Docker executable found - setup docker"

docker_image=ceph/demo:tag-build-master-jewel-ubuntu-16.04

echo "Fetch recent ${docker_image} docker image"
docker pull ${docker_image}

# retrieve current folder to place the config in the parent folder
thisFolder=`echo $0 | sed "s_env/start-swift-ceph.sh__"`

if [ -z "$thisFolder" ]; then
    thisFolder="."
fi;

echo "thisFolder is '$thisFolder'"
env="/home/travis/build/owncloud/core/apps/files_primary_swift/tests/env"
echo "env is '$env'"

port=5034

user=test
pass=testing
tenant=testenant
region=testregion
service=testceph

for netdev in /sys/class/net/*; do
  netdev=${netdev##*/}
  if [[ $netdev != 'lo' ]]; then
    break
  fi
done
subnet=$(ip addr show $netdev | sed -n 's/.*inet \([0-9\.]*\/[0-9]*\) .*/\1/p')

ip_address=${subnet%%/*}
  : ${MON_IP:=${ip_address}}
  : ${CEPH_NETWORK:=${subnet}}

container=`docker run --net=host -d \
    -e MON_IP=${MON_IP} \
    -e CEPH_PUBLIC_NETWORK=${CEPH_NETWORK} \
    -e CEPH_DEMO_UID=owncloud  \
    -e RGW_CIVETWEB_PORT=${port} \
    -e OSD_SIZE=300 \
    ${docker_image}`


host=$(docker inspect --format="{{.NetworkSettings.IPAddress}}" "$container")


echo "${docker_image} container: $container"

# put container IDs into a file to drop them after the test run (keep in mind that multiple tests run in parallel on the same host)
echo $container >> $thisFolder/dockerContainerCeph.swift

echo -n "Waiting for ceph initialization"
if ! "$thisFolder"/env/wait-for-connection ${MON_IP} ${port} 500; then
    echo "[ERROR] Waited 500 seconds, no response" >&2
    docker logs $container
    exit 1
fi
echo "Waiting another 15 seconds"
sleep 15

cat > $thisFolder/swift.config.php <<DELIM
<?php
\$CONFIG = array (
'objectstore' => array(
	'class' => 'OC\\Files\\ObjectStore\\Swift',
	'arguments' => array(
		'username' => '$user',
		'password' => '$pass',
		'container' => 'owncloud-autotest',
	    'objectPrefix' => 'autotest:oid:urn:',
		'autocreate' => true,
		'region' => '$region',
		'url' => 'http://$MON_IP:$port/v2.0',
		'tenantName' => '$tenant',
		'serviceName' => '$service',
	),
),
);

DELIM

if [ -n "$DEBUG" ]; then
    echo "############## DEBUG info ###############"
    echo "### Docker info"
    docker info
    echo "### Docker images"
    docker images
    echo "### current mountpoints"
    mount
    echo "### contents of $thisFolder/swift.config.php"
    cat $thisFolder/swift.config.php
    echo "### contents of $thisFolder/dockerContainerCeph.swift"
    cat $thisFolder/dockerContainerCeph.swift
    echo "### docker logs"
    docker logs $container
    echo "############## DEBUG info end ###########"
fi
