#!/bin/bash
# Run selected scenarios for one distribution inside a Docker container.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/docker/lib/common.sh
source "${SCRIPT_DIR}/common.sh"

# shellcheck source=tests/docker/scenarios/install.sh
source "${DOCKER_TEST_ROOT}/scenarios/install.sh"
# shellcheck source=tests/docker/scenarios/add-user.sh
source "${DOCKER_TEST_ROOT}/scenarios/add-user.sh"
# shellcheck source=tests/docker/scenarios/remove-user.sh
source "${DOCKER_TEST_ROOT}/scenarios/remove-user.sh"
# shellcheck source=tests/docker/scenarios/uninstall.sh
source "${DOCKER_TEST_ROOT}/scenarios/uninstall.sh"
# shellcheck source=tests/docker/scenarios/duplicate-user.sh
source "${DOCKER_TEST_ROOT}/scenarios/duplicate-user.sh"

DIST_SLUG="${DIST_SLUG:?DIST_SLUG is required}"
DOCKER_IMAGE="${DOCKER_IMAGE:?DOCKER_IMAGE is required}"
SCENARIO="${SCENARIO:-all}"
LOG_FILE="${LOG_FILE:-}"

run_scenario() {
	local name=$1
	case "${name}" in
	install) scenario_install ;;
	add | add-user) scenario_add_user ;;
	remove | remove-user) scenario_remove_user ;;
	uninstall) scenario_uninstall ;;
	duplicate | duplicate-user) scenario_duplicate_user ;;
	*)
		log_error "Unknown scenario: ${name}"
		return 1
		;;
	esac
}

run_all_scenarios() {
	run_scenario install || return 1
	run_scenario add-user || return 1
	run_scenario remove-user || return 1
	run_scenario uninstall || return 1
}

show_dist_help() {
	cat <<EOF
Usage: ${DIST_SLUG}.sh [OPTIONS]

Distribution: ${DIST_SLUG}
Image: ${DOCKER_IMAGE}

OPTIONS:
    --scenario NAME    install | add | remove | uninstall | duplicate | all (default: all)
    --keep-container   Do not remove the container when finished
    --verbose          Show installer output
    --trace            Record full installer session to trace log (see below)
    --help             Show this help

Trace log inside container: /tmp/3proxy-test-trace.log
Watch live: docker exec -it CONTAINER tail -f /tmp/3proxy-test-trace.log
EOF
}

parse_dist_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--scenario)
			SCENARIO=$2
			shift 2
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
			show_dist_help
			exit 0
			;;
		*)
			log_error "Unknown option: $1"
			show_dist_help
			exit 1
			;;
		esac
	done
}

run_dist_tests() {
	local container_name
	container_name="3proxy-test-${DIST_SLUG}-$$"

	log "=========================================="
	log "Distribution: ${DIST_SLUG} (${DOCKER_IMAGE})"
	log "Scenario: ${SCENARIO}"
	log "=========================================="

	start_container "${DOCKER_IMAGE}" "${container_name}"
	copy_installer_to_container

	local result=0
	if [[ "${SCENARIO}" == "all" ]]; then
		run_all_scenarios || result=1
	else
		run_scenario "${SCENARIO}" || result=1
	fi

	if [[ ${result} -eq 0 ]]; then
		log "All scenarios passed for ${DIST_SLUG}"
	else
		log_error "Tests failed for ${DIST_SLUG}"
	fi

	stop_container
	return "${result}"
}

main() {
	parse_dist_args "$@"
	check_prerequisites

	local log_path
	log_path="${DOCKER_TEST_LOGS_DIR}/${DIST_SLUG}-$(date +%Y%m%d-%H%M%S).log"
	LOG_FILE="${log_path}"
	mkdir -p "${DOCKER_TEST_LOGS_DIR}"

	set +e
	run_dist_tests 2>&1 | tee -a "${LOG_FILE}"
	local result=${PIPESTATUS[0]}
	set -e
	exit "${result}"
}

main "$@"
