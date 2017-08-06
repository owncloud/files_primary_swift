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
# @copyright 2015-2016 ownCloud

if ! command -v docker >/dev/null 2>&1; then
    echo "No docker executable found - skipped docker setup"
    exit 0;
fi

echo "Docker executable found - setup docker"

docker_image=xenopathic/ceph-keystone

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

# create readiness notification socket
notify_sock=$(readlink -f "$thisFolder"/dockerContainerCeph.swift-ceph.sock)
rm -f "$notify_sock" # in case an unfinished test left one behind
mkfifo "$notify_sock"

port=5034

user=test
pass=testing
tenant=testenant
region=testregion
service=testceph

container=`docker run -d \
    -e KEYSTONE_PUBLIC_PORT=${port} \
    -e KEYSTONE_ADMIN_USER=${user} \
    -e KEYSTONE_ADMIN_PASS=${pass} \
    -e KEYSTONE_ADMIN_TENANT=${tenant} \
    -e KEYSTONE_ENDPOINT_REGION=${region} \
    -e KEYSTONE_SERVICE=${service} \
    -e OSD_SIZE=300 \
    -v "$notify_sock":/run/notifyme.sock \
    --privileged \
    ${docker_image}`

host=$(docker inspect --format="{{.NetworkSettings.IPAddress}}" "$container")


echo "${docker_image} container: $container"

# put container IDs into a file to drop them after the test run (keep in mind that multiple tests run in parallel on the same host)
echo $container >> $thisFolder/dockerContainerCeph.swift

echo -n "Waiting for ceph initialization"
ready=$(timeout 500 cat "$notify_sock")
if [[ $ready != 'READY=1' ]]; then
    echo "[ERROR] Waited 500 seconds, no response" >&2
    docker logs $container
    exit 1
fi
if ! "$thisFolder"/wait-for-connection ${host} 80 500; then
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
		'url' => 'http://$host:$port/v2.0',
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
