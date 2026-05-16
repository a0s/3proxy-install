#!/bin/bash
# Inspect a running 3proxy Docker test container.
# Usage: ./tests/docker/debug-container.sh [CONTAINER_NAME]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER="${1:-}"

if [[ -z "${CONTAINER}" ]]; then
	CONTAINER=$(docker ps --filter "name=3proxy-test-" --format '{{.Names}}' | head -1)
fi

if [[ -z "${CONTAINER}" ]]; then
	echo "No running 3proxy-test container. Pass a name or start tests with --keep-container." >&2
	exit 1
fi

pid=$(docker exec "${CONTAINER}" bash -c 'pgrep -f "/tmp/3proxy-install.sh" | head -1' 2>/dev/null || true)

echo "=== Container: ${CONTAINER} ==="
docker exec "${CONTAINER}" bash -c 'echo "OS: $(. /etc/os-release; echo $PRETTY_NAME)"; command -v systemctl; systemctl is-active 3proxy 2>/dev/null || true'

echo ""
echo "=== Live trace (installer I/O) ==="
echo "  docker exec -it ${CONTAINER} tail -f /tmp/3proxy-test-trace.log"
if docker exec "${CONTAINER}" test -f /tmp/3proxy-test-trace.log 2>/dev/null; then
	echo "--- last 40 lines ---"
	docker exec "${CONTAINER}" tail -40 /tmp/3proxy-test-trace.log
else
	echo "(trace file not created yet — run tests with --trace)"
fi

echo ""
echo "=== Last piped answers ==="
docker exec "${CONTAINER}" bash -c 'if [[ -f /tmp/3proxy-test-answers.txt ]]; then nl -ba /tmp/3proxy-test-answers.txt; od -c /tmp/3proxy-test-answers.txt | head -5; else echo "(none)"; fi' 2>/dev/null

echo ""
echo "=== Users file ==="
docker exec "${CONTAINER}" cat /etc/3proxy/3proxy.cfg.users 2>/dev/null || echo "(missing)"

if [[ -n "${pid}" ]]; then
	echo ""
	echo "=== Installer PID ${pid} ==="
	docker exec "${CONTAINER}" bash -c "ps -o pid,pcpu,stat,etime,cmd -p ${pid}; echo; ls -la /proc/${pid}/fd"
	echo ""
	echo "=== strace (optional, inside container) ==="
	echo "  docker exec -it -u 0 ${CONTAINER} bash -c 'apt-get update && apt-get install -y strace && strace -p ${pid} -f -e trace=read,write -s 120'"
else
	echo ""
	echo "=== No running installer process ==="
fi

echo ""
echo "Shell: docker exec -it -u 0 ${CONTAINER} bash"
