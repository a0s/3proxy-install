#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DIST_SLUG="fedora-43"
export DOCKER_IMAGE="${DOCKER_IMAGE:-fedora:43}"
exec "${SCRIPT_DIR}/../lib/run-dist.sh" "$@"
