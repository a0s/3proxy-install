#!/bin/bash
# Orchestrator for Docker-based multi-OS installer tests.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="${SCRIPT_DIR}/dist"

PARALLEL=false
VERBOSE=false
TRACE=false
KEEP_CONTAINER=false
SCENARIO="all"
SELECTED_DISTS=()

show_help() {
	cat <<EOF
Usage: $0 [OPTIONS]

Run 3proxy-install Docker tests with a fake systemctl stub.

OPTIONS:
    --dist NAME         Run only this distribution (repeatable), e.g. ubuntu-22.04
    --scenario NAME     Passed to dist scripts: install | add | remove | uninstall | duplicate | all
    --parallel          Run selected distributions in parallel
    --keep-container    Keep containers after tests (for debugging)
    --verbose           Show installer output inside containers
    --trace             Log all installer I/O to tests/docker/logs/*-trace.log
    --help              Show this help

With --trace, watch live in another terminal:
    docker exec -it CONTAINER_NAME tail -f /tmp/3proxy-test-trace.log

EXAMPLES:
    $0
    $0 --dist ubuntu-24.04 --scenario install
    $0 --parallel --dist ubuntu-22.04 --dist ubuntu-24.04
    ${DIST_DIR}/ubuntu-22.04.sh --scenario add
EOF
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--dist)
			SELECTED_DISTS+=("$2")
			shift 2
			;;
		--scenario)
			SCENARIO=$2
			shift 2
			;;
		--parallel)
			PARALLEL=true
			shift
			;;
		--keep-container)
			KEEP_CONTAINER=true
			shift
			;;
		--verbose)
			VERBOSE=true
			shift
			;;
		--trace)
			TRACE=true
			shift
			;;
		--help)
			show_help
			exit 0
			;;
		*)
			echo "Unknown option: $1" >&2
			show_help
			exit 1
			;;
		esac
	done
}

discover_dists() {
	local dist
	for dist in "${DIST_DIR}"/*.sh; do
		[[ -f "${dist}" ]] || continue
		basename "${dist}" .sh
	done
}

resolve_dist_scripts() {
	local -a scripts=()
	local slug script

	if [[ ${#SELECTED_DISTS[@]} -eq 0 ]]; then
		while IFS= read -r slug; do
			scripts+=("${DIST_DIR}/${slug}.sh")
		done < <(discover_dists | sort)
	else
		for slug in "${SELECTED_DISTS[@]}"; do
			script="${DIST_DIR}/${slug}.sh"
			if [[ ! -f "${script}" ]]; then
				echo "Unknown distribution script: ${script}" >&2
				exit 1
			fi
			scripts+=("${script}")
		done
	fi

	printf '%s\n' "${scripts[@]}"
}

run_dist_script() {
	local script=$1
	local extra_args=()

	extra_args+=(--scenario "${SCENARIO}")
	if [[ "${KEEP_CONTAINER}" == "true" ]]; then
		extra_args+=(--keep-container)
	fi
	if [[ "${VERBOSE}" == "true" ]]; then
		extra_args+=(--verbose)
	fi

	VERBOSE="${VERBOSE}" TRACE="${TRACE}" KEEP_CONTAINER="${KEEP_CONTAINER}" bash "${script}" "${extra_args[@]}"
}

main() {
	parse_args "$@"

	if ! command -v docker &>/dev/null; then
		echo "docker is not installed or not in PATH" >&2
		exit 1
	fi

	dist_scripts=()
	while IFS= read -r script; do
		[[ -n "${script}" ]] && dist_scripts+=("${script}")
	done < <(resolve_dist_scripts)
	if [[ ${#dist_scripts[@]} -eq 0 ]]; then
		echo "No distribution scripts found in ${DIST_DIR}" >&2
		exit 1
	fi

	chmod +x "${SCRIPT_DIR}"/stub/systemctl
	chmod +x "${SCRIPT_DIR}"/dist/*.sh "${SCRIPT_DIR}"/scenarios/*.sh "${SCRIPT_DIR}"/run.sh 2>/dev/null || true

	local failed=0

	if [[ "${PARALLEL}" == "true" ]]; then
		local -a pids=()
		local script
		for script in "${dist_scripts[@]}"; do
			run_dist_script "${script}" &
			pids+=($!)
		done
		local pid
		for pid in "${pids[@]}"; do
			if ! wait "${pid}"; then
				failed=1
			fi
		done
	else
		local script
		for script in "${dist_scripts[@]}"; do
			if ! run_dist_script "${script}"; then
				failed=1
			fi
		done
	fi

	if [[ ${failed} -ne 0 ]]; then
		echo "One or more distribution test runs failed" >&2
		exit 1
	fi

	echo "All distribution test runs passed"
}

main "$@"
