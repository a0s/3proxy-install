#!/bin/bash
# Scenario: add a user via post-install menu.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/docker/lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

scenario_add_user() {
	local test_user
	test_user="${ADD_TEST_USER:-$(unique_client_name add)}"

	log "Scenario: add-user (${test_user})"

	if ! container_test -f /etc/3proxy/params; then
		log_error "3proxy is not installed (missing /etc/3proxy/params)"
		return 1
	fi

	if ! run_installer_with_input "1" "${test_user}" "1"; then
		log_error "Add user command failed"
		return 1
	fi

	if ! user_exists_in_container "${test_user}"; then
		log_error "User was not added: ${test_user}"
		return 1
	fi

	export ADD_TEST_USER="${test_user}"
	log "Scenario add-user: passed"
	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	check_prerequisites
	if [[ -z "${CONTAINER_NAME:-}" ]]; then
		log_error "CONTAINER_NAME must be set"
		exit 1
	fi
	scenario_add_user
fi
