#!/bin/bash

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_SCRIPT="$PROJECT_ROOT/3proxy-install.sh"
LOG_FILE="$SCRIPT_DIR/test-results.log"
VERBOSE=false
SKIP_INSTALL=false
SKIP_MENU=false

log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_error() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

log_verbose() {
	if [[ "$VERBOSE" == "true" ]]; then
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] VERBOSE: $*" | tee -a "$LOG_FILE"
	fi
}

show_help() {
	cat <<EOF
Usage: $0 [OPTIONS]

Test 3proxy-install.sh on the local host (Ubuntu).

This script must be run with sudo privileges.

OPTIONS:
    --skip-install        Skip installation stage
    --skip-menu           Skip menu testing stage
    --verbose             Enable verbose output
    --help                Show this help message
EOF
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--skip-install)
			SKIP_INSTALL=true
			shift
			;;
		--skip-menu)
			SKIP_MENU=true
			shift
			;;
		--verbose)
			VERBOSE=true
			shift
			;;
		--help)
			show_help
			exit 0
			;;
		*)
			log_error "Unknown option: $1"
			show_help
			exit 1
			;;
		esac
	done
}

check_prerequisites() {
	# Check if install script exists
	if [[ ! -f "$INSTALL_SCRIPT" ]]; then
		log_error "Install script not found: $INSTALL_SCRIPT"
		exit 1
	fi

	# Check if we can use sudo (for commands that need root)
	if ! sudo -n true 2>/dev/null; then
		log_verbose "sudo will require password for some operations"
	fi

	# Check OS is Ubuntu
	if [[ ! -f /etc/os-release ]]; then
		log_error "Cannot determine OS (no /etc/os-release)"
		exit 1
	fi

	source /etc/os-release
	if [[ "${ID}" != "ubuntu" ]]; then
		log_error "This test script is designed for Ubuntu. Detected OS: ${ID}"
		log_error "For testing on other OS, please use the Docker-based test script"
		exit 1
	fi

	log_verbose "Detected OS: ${PRETTY_NAME} (${ID})"

	# Check if curl is available
	if ! command -v curl &>/dev/null; then
		log_error "curl is not installed (required prerequisite)"
		exit 1
	fi

	# Check if systemd is available
	if ! command -v systemctl &>/dev/null; then
		log_error "systemctl is not available (required for 3proxy service)"
		exit 1
	fi
}

cleanup_3proxy() {
	log_verbose "Cleaning up 3proxy installation"

	# Stop service if it exists and is running
	sudo systemctl stop 3proxy &>/dev/null || true

	# Disable service if it exists
	sudo systemctl disable 3proxy &>/dev/null || true

	# Kill any remaining 3proxy processes
	sudo pkill -9 3proxy &>/dev/null || true

	# Remove service file and symlinks
	sudo rm -f /etc/systemd/system/3proxy.service &>/dev/null || true
	sudo rm -f /etc/systemd/system/multi-user.target.wants/3proxy.service &>/dev/null || true
	sudo systemctl daemon-reload &>/dev/null || true

	# Remove binary
	sudo rm -f /usr/local/bin/3proxy &>/dev/null || true

	# Remove configuration directory completely
	sudo rm -rf /etc/3proxy &>/dev/null || true

	log_verbose "Cleanup completed"
}

test_installation() {
	log "Testing installation on local host"

	# Aggressively clean up any existing installation
	log_verbose "Cleaning up any existing 3proxy installation"
	cleanup_3proxy

	# Also ensure the directory doesn't exist at all
	if sudo test -d /etc/3proxy 2>/dev/null; then
		log_verbose "Removing /etc/3proxy directory completely"
		sudo rm -rf /etc/3proxy
	fi

	sleep 2

	log_verbose "Running installation with automated answers"
	# Use timestamp + PID + random number for maximum uniqueness
	local test_user="testuser_$(date +%s)_$$_${RANDOM}_${RANDOM}"
	local server_ip
	server_ip=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | awk '{print $1}' | head -1)
	if [[ -z "$server_ip" ]]; then
		server_ip=$(ip -6 addr | sed -ne 's|^.* inet6 \([^/]*\)/.* scope global.*$|\1|p' | head -1)
	fi
	if [[ -z "$server_ip" ]]; then
		server_ip="127.0.0.1"
	fi

	log_verbose "Using server IP: $server_ip"

	# Use printf to pipe answers to the install script
	if ! printf '%s\n' "$server_ip" "1" "1" "1" "a" "$test_user" "1" | sudo bash "$INSTALL_SCRIPT"; then
		log_error "Installation failed"
		cleanup_3proxy
		return 1
	fi

	log_verbose "Verifying installation"

	# Check binary exists
	if ! sudo test -f /usr/local/bin/3proxy 2>/dev/null; then
		log_error "Binary file not found: /usr/local/bin/3proxy"
		cleanup_3proxy
		return 1
	fi

	# Check config file exists
	if ! sudo test -f /etc/3proxy/3proxy.cfg 2>/dev/null; then
		log_error "Configuration file not found: /etc/3proxy/3proxy.cfg"
		cleanup_3proxy
		return 1
	fi

	# Check service is running
	if ! sudo systemctl is-active --quiet 3proxy 2>/dev/null; then
		log_error "3proxy service is not running"
		log_verbose "Service status:"
		sudo systemctl status 3proxy --no-pager -l || true
		cleanup_3proxy
		return 1
	fi

	# Check process is running
	if ! pgrep -x 3proxy &>/dev/null; then
		log_error "3proxy process is not running"
		cleanup_3proxy
		return 1
	fi

	log "Installation test passed"
	return 0
}

test_menu_add_user() {
	# Use timestamp + random number for more uniqueness
	local test_user="testuser_$(date +%s)_$$_$RANDOM"

	log_verbose "Testing menu: Add user ($test_user)"
	if ! printf '%s\n' "1" "$test_user" "1" | sudo bash "$INSTALL_SCRIPT"; then
		log_error "Failed to add user via menu"
		return 1
	fi

	if ! sudo grep -q "^users $test_user:" /etc/3proxy/3proxy.cfg.users 2>/dev/null; then
		log_error "User was not added to configuration file"
		return 1
	fi

	log_verbose "User added successfully: $test_user"
	return 0
}

test_menu_remove_user() {
	log_verbose "Testing menu: Remove user"
	local user_count
	user_count=$(sudo grep -c "^users " /etc/3proxy/3proxy.cfg.users 2>/dev/null || echo "0")

	if [[ "$user_count" == "0" ]]; then
		log_verbose "No users to remove, adding one first"
		if ! test_menu_add_user; then
			log_error "Failed to add user for removal test"
			return 1
		fi
		user_count=1
	fi

	if ! printf '%s\n' "2" "1" | sudo bash "$INSTALL_SCRIPT"; then
		log_error "Failed to remove user via menu"
		return 1
	fi

	local new_count
	new_count=$(sudo grep -c "^users " /etc/3proxy/3proxy.cfg.users 2>/dev/null || echo "0")

	if [[ "$new_count" -ge "$user_count" ]]; then
		log_error "User was not removed from configuration file"
		return 1
	fi

	log_verbose "User removed successfully"
	return 0
}

test_menu_commands() {
	log "Testing menu commands"

	if ! test_menu_add_user; then
		return 1
	fi

	if ! test_menu_remove_user; then
		return 1
	fi

	log "Menu tests passed"
	return 0
}

run_tests() {
	local install_result=0
	local menu_result=0

	log "=========================================="
	log "Testing 3proxy-install.sh on local host"
	log "=========================================="

	if [[ "$SKIP_INSTALL" != "true" ]]; then
		if test_installation; then
			log "✓ Installation test passed"
			install_result=0
		else
			log_error "✗ Installation test failed"
			install_result=1
		fi
	else
		log "Skipping installation test (--skip-install)"
		# Check if 3proxy is already installed
		if ! sudo test -f /etc/3proxy/params 2>/dev/null; then
			log_error "3proxy is not installed and --skip-install was specified"
			return 1
		fi
		install_result=0
	fi

	if [[ "$SKIP_MENU" != "true" ]] && [[ "$install_result" -eq 0 ]]; then
		if test_menu_commands; then
			log "✓ Menu tests passed"
			menu_result=0
		else
			log_error "✗ Menu tests failed"
			menu_result=1
		fi
	else
		log "Skipping menu tests (--skip-menu or installation failed)"
		menu_result=0
	fi

	# Cleanup after tests
	if [[ "$SKIP_INSTALL" != "true" ]]; then
		cleanup_3proxy
	fi

	if [[ $install_result -eq 0 ]] && [[ $menu_result -eq 0 ]]; then
		return 0
	else
		return 1
	fi
}

main() {
	parse_args "$@"
	check_prerequisites

	log "Starting 3proxy-install test suite"
	log "=========================================="

	if run_tests; then
		log "=========================================="
		log "Test Summary"
		log "=========================================="
		log "All tests passed!"
		log "=========================================="
		exit 0
	else
		log "=========================================="
		log "Test Summary"
		log "=========================================="
		log_error "Some tests failed"
		log "=========================================="
		exit 1
	fi
}

main "$@"
