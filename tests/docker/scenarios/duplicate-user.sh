#!/bin/bash
# Scenario: reject duplicate client name, then accept a new name.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/docker/lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

scenario_duplicate_user() {
	local dup_name unique_name

	if ! container_test -f /etc/3proxy/params; then
		log_error "3proxy is not installed (missing /etc/3proxy/params)"
		return 1
	fi

	dup_name="${DUP_TEST_USER:-$(unique_client_name dup)}"
	unique_name="${DUP_TEST_USER_ALT:-$(unique_client_name dupalt)}"

	log "Scenario: duplicate-user (dup=${dup_name}, alt=${unique_name})"

	if ! run_installer_with_input "1" "${dup_name}" "1"; then
		log_error "Failed to create initial user for duplicate test"
		return 1
	fi

	if ! user_exists_in_container "${dup_name}"; then
		log_error "Initial user was not created: ${dup_name}"
		return 1
	fi

	local before
	before=$(count_users_in_container)

	if ! run_installer_with_input "1" "${dup_name}" "${unique_name}" "1"; then
		log_error "Failed while adding user with duplicate-name retry"
		return 1
	fi

	if ! user_exists_in_container "${unique_name}"; then
		log_error "Alternate user was not added: ${unique_name}"
		return 1
	fi

	if ! user_exists_in_container "${dup_name}"; then
		log_error "Original user disappeared after duplicate attempt"
		return 1
	fi

	local after
	after=$(count_users_in_container)
	if [[ "${after}" -le "${before}" ]]; then
		log_error "User count did not increase after duplicate retry (${before} -> ${after})"
		return 1
	fi

	log "Scenario duplicate-user: passed"
	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	check_prerequisites
	if [[ -z "${CONTAINER_NAME:-}" ]]; then
		log_error "CONTAINER_NAME must be set"
		exit 1
	fi
	scenario_duplicate_user
fi
