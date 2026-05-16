#!/bin/bash
# Docker container lifecycle helpers.

[[ -n "${DOCKER_TEST_CONTAINER_LOADED:-}" ]] && return 0
DOCKER_TEST_CONTAINER_LOADED=1

set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-}"
DOCKER_IMAGE="${DOCKER_IMAGE:-}"
# Never use the host PATH inside containers (breaks stub lookup on macOS).
CONTAINER_PATH="${DOCKER_TEST_STUB_MOUNT:-/opt/3proxy-test/bin}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
INSTALLER_TIMEOUT="${INSTALLER_TIMEOUT:-900}"

container_exec() {
	if [[ -z "${CONTAINER_NAME}" ]]; then
		log_error "CONTAINER_NAME is not set"
		return 1
	fi
	docker exec -u 0 -e "PATH=${CONTAINER_PATH}" "${CONTAINER_NAME}" "$@"
}

container_exec_pipe() {
	if [[ -z "${CONTAINER_NAME}" ]]; then
		log_error "CONTAINER_NAME is not set"
		return 1
	fi
	docker exec -i -u 0 -e "PATH=${CONTAINER_PATH}" "${CONTAINER_NAME}" "$@"
}

container_test() {
	container_exec test "$@"
}

container_grep() {
	container_exec grep "$@"
}

start_container() {
	local image=$1
	local name=$2

	DOCKER_IMAGE="${image}"
	CONTAINER_NAME="${name}"

	log "Starting container ${CONTAINER_NAME} (${DOCKER_IMAGE})"
	docker rm -f "${CONTAINER_NAME}" &>/dev/null || true

	docker run -d --name "${CONTAINER_NAME}" \
		-e "PATH=${CONTAINER_PATH}" \
		-v "${DOCKER_TEST_STUB_HOST}:${DOCKER_TEST_STUB_MOUNT}:ro" \
		"${DOCKER_IMAGE}" \
		sleep infinity

	local retries=30
	while ((retries > 0)); do
		if docker exec "${CONTAINER_NAME}" true &>/dev/null; then
			return 0
		fi
		sleep 1
		retries=$((retries - 1))
	done

	log_error "Container ${CONTAINER_NAME} did not become ready"
	return 1
}

copy_installer_to_container() {
	log_verbose "Copying installer into container"
	docker cp "${DOCKER_TEST_INSTALL_SCRIPT_HOST}" "${CONTAINER_NAME}:${DOCKER_TEST_INSTALL_SCRIPT_CONTAINER}"
	container_exec chmod +x "${DOCKER_TEST_INSTALL_SCRIPT_CONTAINER}"
	container_exec chmod +x "${DOCKER_TEST_STUB_MOUNT}/run-traced.sh" "${DOCKER_TEST_STUB_MOUNT}/systemctl" 2>/dev/null || true
	if [[ "${TRACE:-false}" == "true" ]]; then
		container_exec bash -c ": > ${DOCKER_TEST_TRACE_LOG_CONTAINER}"
		print_live_trace_hint
	fi
}

stop_container() {
	if [[ -z "${CONTAINER_NAME}" ]]; then
		return 0
	fi

	if [[ "${KEEP_CONTAINER}" == "true" ]]; then
		log "Keeping container for debugging: ${CONTAINER_NAME}"
		log "Shell: docker exec -it -u 0 ${CONTAINER_NAME} bash"
		return 0
	fi

	log_verbose "Removing container ${CONTAINER_NAME}"
	docker rm -f "${CONTAINER_NAME}" &>/dev/null || true
}
