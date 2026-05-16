#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DIST_SLUG="centos-stream-10"
export DOCKER_IMAGE="${DOCKER_IMAGE:-quay.io/centos/centos:stream10}"
exec "${SCRIPT_DIR}/../lib/run-dist.sh" "$@"
