#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DIST_SLUG="debian-13"
export DOCKER_IMAGE="${DOCKER_IMAGE:-debian:13}"
exec "${SCRIPT_DIR}/../lib/run-dist.sh" "$@"
