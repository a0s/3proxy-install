#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DIST_SLUG="ubuntu-18.04"
export DOCKER_IMAGE="${DOCKER_IMAGE:-ubuntu:18.04}"
exec "${SCRIPT_DIR}/../lib/run-dist.sh" "$@"
