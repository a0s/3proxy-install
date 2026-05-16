#!/bin/bash
# Scenario: uninstall 3proxy via menu option 3.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/docker/lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

scenario_uninstall() {
	log "Scenario: uninstall"

	if ! container_test -f /etc/3proxy/params; then
		log_error "3proxy is not installed (missing /etc/3proxy/params)"
		return 1
	fi

	if ! run_installer_with_input "3" "y"; then
		log_error "Uninstall command failed"
		return 1
	fi

	assert_container_missing /etc/3proxy "Config directory still exists" || return 1
	assert_container_missing /usr/local/bin/3proxy "Binary still exists" || return 1
	assert_container_missing /etc/systemd/system/3proxy.service "Service unit still exists" || return 1

	if stub_is_active_in_container; then
		log_error "Stub still reports 3proxy as active after uninstall"
		return 1
	fi

	log "Scenario uninstall: passed"
	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	check_prerequisites
	if [[ -z "${CONTAINER_NAME:-}" ]]; then
		log_error "CONTAINER_NAME must be set"
		exit 1
	fi
	scenario_uninstall
fi
