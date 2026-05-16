#!/bin/bash
# Shared helpers for Docker-based 3proxy-install tests.

[[ -n "${DOCKER_TEST_COMMON_LOADED:-}" ]] && return 0
DOCKER_TEST_COMMON_LOADED=1

set -euo pipefail

DOCKER_TEST_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_TEST_ROOT="$(cd "${DOCKER_TEST_LIB_DIR}/.." && pwd)"
DOCKER_TEST_PROJECT_ROOT="$(cd "${DOCKER_TEST_ROOT}/../.." && pwd)"
DOCKER_TEST_INSTALL_SCRIPT_HOST="${DOCKER_TEST_PROJECT_ROOT}/3proxy-install.sh"
DOCKER_TEST_INSTALL_SCRIPT_CONTAINER="/tmp/3proxy-install.sh"
DOCKER_TEST_STUB_MOUNT="/opt/3proxy-test/bin"
DOCKER_TEST_STUB_HOST="${DOCKER_TEST_ROOT}/stub"
DOCKER_TEST_LOGS_DIR="${DOCKER_TEST_ROOT}/logs"
DOCKER_TEST_SERVER_IP="${DOCKER_TEST_SERVER_IP:-127.0.0.1}"

VERBOSE="${VERBOSE:-false}"
TRACE="${TRACE:-false}"
KEEP_CONTAINER="${KEEP_CONTAINER:-false}"
DOCKER_TEST_TRACE_LOG_CONTAINER="/tmp/3proxy-test-trace.log"

log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_error() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

log_verbose() {
	if [[ "${VERBOSE}" == "true" ]]; then
		log "VERBOSE: $*"
	fi
}

unique_client_name() {
	local prefix="${1:-user}"
	echo "${prefix}_$(date +%s)_$$_${RANDOM}"
}

assert_container_file() {
	local path=$1
	local message=${2:-"Missing file: ${path}"}

	if ! container_test -f "${path}"; then
		log_error "${message}"
		return 1
	fi
	return 0
}

assert_container_missing() {
	local path=$1
	local message=${2:-"File should not exist: ${path}"}

	if container_test -e "${path}"; then
		log_error "${message}"
		return 1
	fi
	return 0
}

count_users_in_container() {
	local count status
	set +e
	count=$(container_exec grep -c '^users ' /etc/3proxy/3proxy.cfg.users 2>/dev/null)
	status=$?
	set -e
	if [[ ${status} -ne 0 ]]; then
		echo 0
	else
		echo "${count}"
	fi
}

user_exists_in_container() {
	local username=$1
	container_grep -q "^users ${username}:" /etc/3proxy/3proxy.cfg.users 2>/dev/null
}

stub_is_active_in_container() {
	container_exec systemctl is-active --quiet 3proxy
}

run_installer_with_input() {
	# Feed answers via a file inside the container. Piping from the host through
	# `docker exec -i` is unreliable on Docker Desktop and can leave the installer
	# spinning on empty `read` when stdin closes early.
	local answers_host answers_container trace_runner
	answers_host="$(mktemp "${TMPDIR:-/tmp}/3proxy-test-answers.XXXXXX")"
	answers_container="/tmp/3proxy-test-answers.txt"
	trace_runner="${DOCKER_TEST_STUB_MOUNT}/run-traced.sh"
	# Unix line endings only (docker cp from macOS must not leave CRLF in usernames).
	printf '%s\n' "$@" | tr -d '\r' >"${answers_host}"

	log_verbose "Running installer with $# input line(s) (timeout=${INSTALLER_TIMEOUT}s, trace=${TRACE})"
	docker cp "${answers_host}" "${CONTAINER_NAME}:${answers_container}" >/dev/null
	rm -f "${answers_host}"

	# stdin must be opened inside the same bash -c as the installer (`timeout` alone breaks fd 0).
	local inner_cmd
	if [[ "${TRACE}" == "true" ]]; then
		inner_cmd="TRACE_LOG=${DOCKER_TEST_TRACE_LOG_CONTAINER} ${trace_runner} ${answers_container} ${DOCKER_TEST_INSTALL_SCRIPT_CONTAINER}"
	else
		inner_cmd="exec 0<${answers_container}; bash ${DOCKER_TEST_INSTALL_SCRIPT_CONTAINER}"
	fi
	local cmd
	cmd="timeout -s KILL ${INSTALLER_TIMEOUT} bash -c $(printf '%q' "${inner_cmd}")"

	local status=0
	set +e
	if [[ "${VERBOSE}" == "true" ]] || [[ "${TRACE}" == "true" ]]; then
		container_exec bash -c "${cmd}"
		status=$?
	else
		container_exec bash -c "${cmd}" &>/dev/null
		status=$?
	fi
	set -e

	if [[ "${TRACE}" == "true" ]]; then
		copy_trace_log_from_container
	fi
	return "${status}"
}

copy_trace_log_from_container() {
	local trace_host
	trace_host="${DOCKER_TEST_LOGS_DIR}/${CONTAINER_NAME:-container}-trace.log"
	mkdir -p "${DOCKER_TEST_LOGS_DIR}"
	docker cp "${CONTAINER_NAME}:${DOCKER_TEST_TRACE_LOG_CONTAINER}" "${trace_host}" 2>/dev/null || true
	log "Trace log (host): ${trace_host}"
}

print_live_trace_hint() {
	log "Live I/O trace: docker exec -it ${CONTAINER_NAME} tail -f ${DOCKER_TEST_TRACE_LOG_CONTAINER}"
	log "Host trace copy:  ${DOCKER_TEST_LOGS_DIR}/${CONTAINER_NAME}-trace.log"
}

run_installer_expect_failure() {
	set +e
	run_installer_with_input "$@"
	local status=$?
	set -e
	return "${status}"
}

check_prerequisites() {
	if ! command -v docker &>/dev/null; then
		log_error "docker is not installed or not in PATH"
		exit 1
	fi

	if [[ ! -f "${DOCKER_TEST_INSTALL_SCRIPT_HOST}" ]]; then
		log_error "Install script not found: ${DOCKER_TEST_INSTALL_SCRIPT_HOST}"
		exit 1
	fi

	if [[ ! -x "${DOCKER_TEST_STUB_HOST}/systemctl" ]]; then
		chmod +x "${DOCKER_TEST_STUB_HOST}/systemctl"
	fi

	mkdir -p "${DOCKER_TEST_LOGS_DIR}"
}

# shellcheck source=tests/docker/lib/container.sh
source "${DOCKER_TEST_LIB_DIR}/container.sh"
