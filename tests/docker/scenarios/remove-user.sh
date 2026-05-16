#!/bin/bash
# Scenario: remove the first listed user via menu.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/docker/lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

scenario_remove_user() {
	local before after

	log "Scenario: remove-user"

	if ! container_test -f /etc/3proxy/params; then
		log_error "3proxy is not installed (missing /etc/3proxy/params)"
		return 1
	fi

	before=$(count_users_in_container)
	if [[ "${before}" -eq 0 ]]; then
		log_error "No users available to remove"
		return 1
	fi

	if ! run_installer_with_input "2" "1"; then
		log_error "Remove user command failed"
		return 1
	fi

	after=$(count_users_in_container)
	if [[ "${after}" -ge "${before}" ]]; then
		log_error "User count did not decrease (${before} -> ${after})"
		return 1
	fi

	log "Scenario remove-user: passed"
	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	check_prerequisites
	if [[ -z "${CONTAINER_NAME:-}" ]]; then
		log_error "CONTAINER_NAME must be set"
		exit 1
	fi
	scenario_remove_user
fi
