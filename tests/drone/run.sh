#!/usr/bin/env bash
set -xeo pipefail

if [[ "$(pwd)" == "$(cd "$(dirname "$0")"; pwd -P)" ]]; then
  echo "Can only be executed from project root!"
  exit 1
fi

declare -x COVERAGE
[[ -z "${COVERAGE}" ]] && COVERAGE="false"

readonly BASE_DIR="$(pwd)"


main () {
  core_path="$(dirname "$(dirname "${BASE_DIR}")")"

  # wait for storage to be ready
  wait-for-it -t 120 ceph:5034

  # go to server root dir
  cd "${core_path}"

  # enable apps
  php occ app:enable files_primary_swift
  php occ app:list

  # copy configuration
  cp "${BASE_DIR}/tests/drone/swift.config.php" config/swift.config.php



  # run unit tests
  if [[ "${COVERAGE}" == "true" ]]; then
    phpdbg -d memory_limit=4096M -rr ./lib/composer/bin/phpunit --configuration tests/phpunit-autotest.xml
  else
    ./lib/composer/bin/phpunit --configuration tests/phpunit-autotest.xml
  fi

}

main