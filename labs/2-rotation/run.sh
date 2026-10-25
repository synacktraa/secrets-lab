#!/usr/bin/env bash
# Experiment 2: password rotation. README.md in this folder explains the timeline.
#
# Starts Postgres 17 in Docker, then changes (rotates) the app's password two
# ways while a fake app keeps connecting, and counts the failed connections.
# scenario.sh holds the timeline; it runs in a second container next to the
# database. Takes about 30 seconds.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
IMAGE="postgres:17-alpine"
NET="rotlab"

command -v docker > /dev/null || { echo "missing: docker. Install Docker: https://docs.docker.com/get-docker/"; exit 1; }
docker info > /dev/null 2>&1 || { echo "Docker is installed but not running. Start it and run this again."; exit 1; }

cleanup() {
  docker rm -f rotlab-db > /dev/null 2>&1
  docker network rm "$NET" > /dev/null 2>&1
}
cleanup
docker network create "$NET" > /dev/null
docker run -d --name rotlab-db --network "$NET" --network-alias db \
  -e POSTGRES_PASSWORD=admin -e POSTGRES_DB=app "$IMAGE" > /dev/null

for mode in in-place two-users; do
  echo "== $mode"
  docker run --rm -i --network "$NET" "$IMAGE" sh -s "$mode" < "$HERE/scenario.sh"
  echo
done
cleanup
