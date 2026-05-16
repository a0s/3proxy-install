#!/bin/bash
# Scenario: fresh installation via piped answers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/docker/lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

scenario_install() {
	local install_user
	install_user="${INSTALL_TEST_USER:-$(unique_client_name install)}"
	export INSTALL_TEST_USER="${install_user}"

	log "Scenario: install (user=${install_user})"

	# After "Press any key" (read -n1) a newline stays in stdin; skip it with a blank line.
	if ! run_installer_with_input \
		"${DOCKER_TEST_SERVER_IP}" \
		"1" "1" "1" \
		"a" "" \
		"${install_user}" \
		"1"; then
		log_error "Installation command failed"
		return 1
	fi

	assert_container_file /usr/local/bin/3proxy "Binary not installed" || return 1
	assert_container_file /etc/3proxy/params "Params file missing" || return 1
	assert_container_file /etc/3proxy/3proxy.cfg "Main config missing" || return 1
	assert_container_file /etc/3proxy/3proxy.cfg.users "Users file missing" || return 1
	assert_container_file /etc/systemd/system/3proxy.service "Systemd unit not generated" || return 1

	if ! user_exists_in_container "${install_user}"; then
		log_error "Install user not found in users file: ${install_user}"
		return 1
	fi

	if ! stub_is_active_in_container; then
		log_error "Stub reports 3proxy service is not active after install"
		return 1
	fi

	log "Scenario install: passed"
	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	check_prerequisites
	if [[ -z "${CONTAINER_NAME:-}" ]]; then
		log_error "CONTAINER_NAME must be set"
		exit 1
	fi
	scenario_install
fi
