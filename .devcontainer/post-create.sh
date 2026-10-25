#!/usr/bin/env bash
# Runs once when the codespace is created: waits for Docker to start, then
# downloads the two images the labs use, so the first run doesn't wait on them.
set -euo pipefail
for _ in $(seq 60); do docker info > /dev/null 2>&1 && break; sleep 1; done
docker pull -q python:3.12-slim
docker pull -q postgres:17-alpine
