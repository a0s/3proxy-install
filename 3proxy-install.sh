#!/bin/bash

# Secure 3proxy server installer
# https://github.com/a0s/3proxy-install

readonly PROXY3_SOURCE_URL="https://github.com/z3apa3a/3proxy/archive/refs/heads/master.tar.gz"
readonly DEFAULT_HTTP_PORT=3128
readonly DEFAULT_SOCKS_PORT=1080
readonly PROXY3_BINARY="/usr/local/bin/3proxy"
readonly PROXY3_CONFIG="/etc/3proxy/3proxy.cfg"
readonly PROXY3_SERVICE="/etc/systemd/system/3proxy.service"
readonly PROXY3_PARAMS="/etc/3proxy/params"
readonly PROXY3_CONFIG_DIR="/etc/3proxy"

RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NC='\033[0m'

function isRoot() {
	if [ "${EUID}" -ne 0 ]; then
		echo "You need to run this script as root"
		exit 1
	fi
}

function checkVirt() {
	if command -v virt-what &>/dev/null; then
		VIRT=$(virt-what)
	else
		VIRT=$(systemd-detect-virt)
	fi
	if [[ ${VIRT} == "openvz" ]]; then
		echo "OpenVZ is not supported"
		exit 1
	fi
	if [[ ${VIRT} == "lxc" ]]; then
		echo "LXC is not supported (yet)."
		exit 1
	fi
}

function checkOS() {
	source /etc/os-release
	OS="${ID}"
	if [[ ${OS} == "debian" || ${OS} == "raspbian" ]]; then
		if [[ ${VERSION_ID} -lt 10 ]]; then
			echo "Your version of Debian (${VERSION_ID}) is not supported. Please use Debian 10 Buster or later"
			exit 1
		fi
		OS=debian
	elif [[ ${OS} == "ubuntu" ]]; then
		RELEASE_YEAR=$(echo "${VERSION_ID}" | cut -d'.' -f1)
		if [[ ${RELEASE_YEAR} -lt 18 ]]; then
			echo "Your version of Ubuntu (${VERSION_ID}) is not supported. Please use Ubuntu 18.04 or later"
			exit 1
		fi
	elif [[ ${OS} == "fedora" ]]; then
		if [[ ${VERSION_ID} -lt 32 ]]; then
			echo "Your version of Fedora (${VERSION_ID}) is not supported. Please use Fedora 32 or later"
			exit 1
		fi
	elif [[ ${OS} == 'centos' ]] || [[ ${OS} == 'almalinux' ]] || [[ ${OS} == 'rocky' ]]; then
		if [[ ${VERSION_ID} == 7* ]]; then
			echo "Your version of CentOS (${VERSION_ID}) is not supported. Please use CentOS 8 or later"
			exit 1
		fi
	elif [[ -e /etc/oracle-release ]]; then
		source /etc/os-release
		OS=oracle
	elif [[ -e /etc/arch-release ]]; then
		OS=arch
	elif [[ -e /etc/alpine-release ]]; then
		OS=alpine
		if ! command -v virt-what &>/dev/null; then
			if ! (apk update && apk add virt-what); then
				echo -e "${RED}Failed to install virt-what. Continuing without virtualization check.${NC}"
			fi
		fi
	else
		echo "Looks like you aren't running this installer on a Debian, Ubuntu, Fedora, CentOS, AlmaLinux, Oracle or Arch Linux system"
		exit 1
	fi
}

function initialCheck() {
	isRoot
	checkOS
	checkVirt
}

function getHomeDirForClient() {
	local CLIENT_NAME=$1

	if [ -z "${CLIENT_NAME}" ]; then
		echo "Error: getHomeDirForClient() requires a client name as argument"
		exit 1
	fi

	if [ -e "/home/${CLIENT_NAME}" ]; then
		HOME_DIR="/home/${CLIENT_NAME}"
	elif [ "${SUDO_USER}" ]; then
		if [ "${SUDO_USER}" == "root" ]; then
			HOME_DIR="/root"
		else
			HOME_DIR="/home/${SUDO_USER}"
		fi
	else
		HOME_DIR="/root"
	fi

	echo "$HOME_DIR"
}

function installPackages() {
	if ! "$@"; then
		echo -e "${RED}Failed to install packages.${NC}"
		echo "Please check your internet connection and package sources."
		exit 1
	fi
}

function installQuestions() {
	echo "Welcome to the 3proxy installer!"
	echo "The git repository is available at: https://github.com/a0s/3proxy-install"
	echo ""
	echo "I need to ask you a few questions before starting the setup."
	echo "You can keep the default options and just press enter if you are ok with them."
	echo ""

	SERVER_PUB_IP=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | awk '{print $1}' | head -1)
	if [[ -z ${SERVER_PUB_IP} ]]; then
		SERVER_PUB_IP=$(ip -6 addr | sed -ne 's|^.* inet6 \([^/]*\)/.* scope global.*$|\1|p' | head -1)
	fi
	read -rp "IPv4 or IPv6 public address: " -e -i "${SERVER_PUB_IP}" SERVER_PUB_IP

	echo ""
	echo "HTTP proxy port:"
	echo "   1) Default: ${DEFAULT_HTTP_PORT}"
	echo "   2) Custom"
	echo "   3) Random [49152-65535]"
	until [[ ${HTTP_PORT_CHOICE} =~ ^[1-3]$ ]]; do
		read -rp "Port choice [1-3]: " -e -i 1 HTTP_PORT_CHOICE
	done
	case $HTTP_PORT_CHOICE in
	1)
		HTTP_PORT="${DEFAULT_HTTP_PORT}"
		;;
	2)
		until [[ ${HTTP_PORT} =~ ^[0-9]+$ ]] && [ "${HTTP_PORT}" -ge 1 ] && [ "${HTTP_PORT}" -le 65535 ]; do
			read -rp "Custom HTTP port [1-65535]: " -e -i ${DEFAULT_HTTP_PORT} HTTP_PORT
		done
		;;
	3)
		HTTP_PORT=$(shuf -i 49152-65535 -n1)
		echo "Random HTTP Port: $HTTP_PORT"
		;;
	esac

	echo ""
	echo "SOCKS proxy port:"
	echo "   1) Default: ${DEFAULT_SOCKS_PORT}"
	echo "   2) Custom"
	echo "   3) Random [49152-65535]"
	until [[ ${SOCKS_PORT_CHOICE} =~ ^[1-3]$ ]]; do
		read -rp "Port choice [1-3]: " -e -i 1 SOCKS_PORT_CHOICE
	done
	case $SOCKS_PORT_CHOICE in
	1)
		SOCKS_PORT="${DEFAULT_SOCKS_PORT}"
		;;
	2)
		until [[ ${SOCKS_PORT} =~ ^[0-9]+$ ]] && [ "${SOCKS_PORT}" -ge 1 ] && [ "${SOCKS_PORT}" -le 65535 ]; do
			read -rp "Custom SOCKS port [1-65535]: " -e -i ${DEFAULT_SOCKS_PORT} SOCKS_PORT
		done
		;;
	3)
		SOCKS_PORT=$(shuf -i 49152-65535 -n1)
		echo "Random SOCKS Port: $SOCKS_PORT"
		;;
	esac

	echo ""
	echo "What DNS resolvers do you want to use with the proxy?"
	echo "   1) Cloudflare (1.1.1.1, 1.0.0.1)"
	echo "   2) Google (8.8.8.8, 8.8.4.4)"
	echo "   3) Quad9 (9.9.9.9, 149.112.112.112)"
	echo "   4) Quad9 uncensored (9.9.9.10, 149.112.112.10)"
	echo "   5) FDN (80.67.169.40, 80.67.169.12)"
	echo "   6) DNS.WATCH (84.200.69.80, 84.200.70.40)"
	echo "   7) OpenDNS (208.67.222.222, 208.67.220.220)"
	echo "   8) Yandex (77.88.8.8, 77.88.8.1)"
	echo "   9) AdGuard (94.140.14.14, 94.140.15.15)"
	echo "  10) NextDNS (45.90.28.167, 45.90.30.167)"
	echo "  11) Custom"
	until [[ ${DNS_CHOICE} =~ ^[1-9]$|^1[01]$ ]]; do
		read -rp "DNS choice [1-11]: " -e -i 1 DNS_CHOICE
	done
	case $DNS_CHOICE in
	1)
		DNS1="1.1.1.1"
		DNS2="1.0.0.1"
		;;
	2)
		DNS1="8.8.8.8"
		DNS2="8.8.4.4"
		;;
	3)
		DNS1="9.9.9.9"
		DNS2="149.112.112.112"
		;;
	4)
		DNS1="9.9.9.10"
		DNS2="149.112.112.10"
		;;
	5)
		DNS1="80.67.169.40"
		DNS2="80.67.169.12"
		;;
	6)
		DNS1="84.200.69.80"
		DNS2="84.200.70.40"
		;;
	7)
		DNS1="208.67.222.222"
		DNS2="208.67.220.220"
		;;
	8)
		DNS1="77.88.8.8"
		DNS2="77.88.8.1"
		;;
	9)
		DNS1="94.140.14.14"
		DNS2="94.140.15.15"
		;;
	10)
		DNS1="45.90.28.167"
		DNS2="45.90.30.167"
		;;
	11)
		until [[ ${DNS1} =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]; do
			read -rp "Primary DNS: " -e DNS1
		done
		until [[ ${DNS2} =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]] || [[ ${DNS2} == "" ]]; do
			read -rp "Secondary DNS (optional): " -e DNS2
		done
		if [[ ${DNS2} == "" ]]; then
			DNS2="${DNS1}"
		fi
		;;
	esac

	echo ""
	echo "Okay, that was all I needed. We are ready to setup your 3proxy server now."
	echo "You will be able to generate a user at the end of the installation."
	read -n1 -r -p "Press any key to continue..."
}

function install3proxy() {
	installQuestions

	echo ""
	echo "Installing build dependencies..."
	if [[ ${OS} == 'ubuntu' ]] || [[ ${OS} == 'debian' ]]; then
		apt-get update
		installPackages apt-get install -y build-essential curl tar
	elif [[ ${OS} == 'fedora' ]]; then
		installPackages dnf install -y gcc make curl tar
	elif [[ ${OS} == 'centos' ]] || [[ ${OS} == 'almalinux' ]] || [[ ${OS} == 'rocky' ]]; then
		installPackages yum install -y gcc make curl tar
	elif [[ ${OS} == 'oracle' ]]; then
		installPackages yum install -y gcc make curl tar
	elif [[ ${OS} == 'arch' ]]; then
		installPackages pacman -S --needed --noconfirm base-devel curl tar
	elif [[ ${OS} == 'alpine' ]]; then
		apk update
		installPackages apk add gcc make curl tar
	fi

	echo ""
	echo "Downloading 3proxy source..."
	cd /tmp || exit 1
	if ! curl -fL --retry 5 -o 3proxy.tar.gz "${PROXY3_SOURCE_URL}"; then
		echo -e "${RED}Failed to download 3proxy source.${NC}"
		exit 1
	fi

	echo "Extracting 3proxy source..."
	if ! tar -xzf 3proxy.tar.gz; then
		echo -e "${RED}Failed to extract 3proxy source.${NC}"
		exit 1
	fi

	echo "Building 3proxy..."
	cd 3proxy-master || exit 1
	if ! ln -sf Makefile.Linux Makefile; then
		echo -e "${RED}Failed to create Makefile symlink.${NC}"
		exit 1
	fi
	if ! make; then
		echo -e "${RED}Failed to build 3proxy.${NC}"
		exit 1
	fi

	echo "Installing 3proxy binary..."
	if ! cp bin/3proxy "${PROXY3_BINARY}"; then
		echo -e "${RED}Failed to install 3proxy binary.${NC}"
		exit 1
	fi
	chmod 755 "${PROXY3_BINARY}"

	echo "Cleaning up build files..."
	cd /tmp || exit 1
	rm -rf 3proxy.tar.gz 3proxy-master

	echo "Creating 3proxy configuration directory..."
	mkdir -p "${PROXY3_CONFIG_DIR}"

	echo "Generating 3proxy configuration file..."
	generateConfig

	echo "Creating systemd service..."
	generateService

	echo "Enabling and starting 3proxy service..."
	systemctl daemon-reload
	systemctl enable 3proxy
	systemctl start 3proxy

	if ! systemctl is-active --quiet 3proxy; then
		echo -e "${ORANGE}WARNING: 3proxy service is not running.${NC}"
		echo "You can check the status with: systemctl status 3proxy"
	else
		echo -e "${GREEN}3proxy service is running.${NC}"
	fi

	saveParams

	echo ""
	echo -e "${GREEN}3proxy installation completed!${NC}"
	echo ""
	echo "You can now add users by running this script again."
	newClient
}

function generateConfig() {
	cat >"${PROXY3_CONFIG}" <<EOF
nserver ${DNS1}
nserver ${DNS2}

log
logformat "L%t%. L%t.%. %N.%p %E %U %C:%c %R:%r %O %I %h %T"

EOF

	if [ -f "${PROXY3_CONFIG}.users" ]; then
		cat "${PROXY3_CONFIG}.users" >>"${PROXY3_CONFIG}"
	fi

	cat >>"${PROXY3_CONFIG}" <<EOF

auth strong
allow *
proxy -p${HTTP_PORT}
socks -p${SOCKS_PORT}
flush
EOF
}

function generateService() {
	cat >"${PROXY3_SERVICE}" <<EOF
[Unit]
Description=3proxy proxy server
Documentation=man:3proxy(1)
After=network.target

[Service]
ExecStart=${PROXY3_BINARY} ${PROXY3_CONFIG}
KillMode=process
Restart=on-failure
LimitNOFILE=65536
LimitNPROC=32768

[Install]
WantedBy=multi-user.target
EOF
}

function saveParams() {
	cat >"${PROXY3_PARAMS}" <<EOF
SERVER_PUB_IP=${SERVER_PUB_IP}
HTTP_PORT=${HTTP_PORT}
SOCKS_PORT=${SOCKS_PORT}
DNS1=${DNS1}
DNS2=${DNS2}
EOF
}

function loadParams() {
	if [ -f "${PROXY3_PARAMS}" ]; then
		source "${PROXY3_PARAMS}"
	else
		echo "Parameters file not found: ${PROXY3_PARAMS}"
		exit 1
	fi
}

function generatePassword() {
	openssl rand -base64 16 | tr -d "=+/" | cut -c1-16
}

function newClient() {
	echo ""
	echo "Client configuration"
	echo ""
	echo "The client name must consist of alphanumeric character(s). It may also include underscores or dashes."

	until [[ ${CLIENT_NAME} =~ ^[a-zA-Z0-9_-]+$ && ${CLIENT_EXISTS} == '0' ]]; do
		read -rp "Client name: " -e CLIENT_NAME
		if [ -f "${PROXY3_CONFIG}.users" ]; then
			CLIENT_EXISTS=$(grep -c "^users ${CLIENT_NAME}:" "${PROXY3_CONFIG}.users" || echo 0)
		else
			CLIENT_EXISTS=0
		fi

		if [[ ${CLIENT_EXISTS} != 0 ]]; then
			echo ""
			echo -e "${ORANGE}A client with the specified name was already created, please choose another name.${NC}"
			echo ""
		fi
	done

	echo ""
	echo "Do you want to set a custom password for this client?"
	echo "   1) Generate random password"
	echo "   2) Set custom password"
	until [[ ${PASS_CHOICE} =~ ^[1-2]$ ]]; do
		read -rp "Password choice [1-2]: " -e -i 1 PASS_CHOICE
	done

	case $PASS_CHOICE in
	1)
		CLIENT_PASSWORD=$(generatePassword)
		;;
	2)
		until [[ ${CLIENT_PASSWORD} =~ ^.+$ ]]; do
			read -rp "Custom password: " -e CLIENT_PASSWORD
		done
		;;
	esac

	if [ ! -f "${PROXY3_CONFIG}.users" ]; then
		touch "${PROXY3_CONFIG}.users"
	fi

	echo "users ${CLIENT_NAME}:CL:${CLIENT_PASSWORD}" >>"${PROXY3_CONFIG}.users"

	generateConfig

	if systemctl is-active --quiet 3proxy; then
		systemctl restart 3proxy
	else
		systemctl start 3proxy
	fi

	echo ""
	echo -e "${GREEN}Client ${CLIENT_NAME} added successfully!${NC}"
	echo ""
	echo "=== Proxy Configuration ==="
	echo ""
	echo "URL Format:"
	echo "  HTTP:  http://${CLIENT_NAME}:${CLIENT_PASSWORD}@${SERVER_PUB_IP}:${HTTP_PORT}"
	echo "  HTTPS: https://${CLIENT_NAME}:${CLIENT_PASSWORD}@${SERVER_PUB_IP}:${HTTP_PORT}"
	echo "  SOCKS: socks5://${CLIENT_NAME}:${CLIENT_PASSWORD}@${SERVER_PUB_IP}:${SOCKS_PORT}"
	echo ""
	echo "Separate Configuration:"
	echo ""
	echo "HTTP/HTTPS Proxy:"
	echo "  Protocol: HTTP / HTTPS"
	echo "  Host: ${SERVER_PUB_IP}"
	echo "  Port: ${HTTP_PORT}"
	echo "  Username: ${CLIENT_NAME}"
	echo "  Password: ${CLIENT_PASSWORD}"
	echo ""
	echo "SOCKS Proxy:"
	echo "  Protocol: SOCKS5"
	echo "  Host: ${SERVER_PUB_IP}"
	echo "  Port: ${SOCKS_PORT}"
	echo "  Username: ${CLIENT_NAME}"
	echo "  Password: ${CLIENT_PASSWORD}"
	echo ""
}

function listClients() {
	if [ ! -f "${PROXY3_CONFIG}.users" ]; then
		echo ""
		echo "You have no existing clients!"
		exit 1
	fi

	NUMBER_OF_CLIENTS=$(grep -c "^users " "${PROXY3_CONFIG}.users" || echo 0)
	if [[ ${NUMBER_OF_CLIENTS} -eq 0 ]]; then
		echo ""
		echo "You have no existing clients!"
		exit 1
	fi

	echo ""
	echo "Existing clients:"
	grep "^users " "${PROXY3_CONFIG}.users" | cut -d' ' -f2 | cut -d':' -f1 | nl -s ') '
}

function removeClient() {
	listClients

	NUMBER_OF_CLIENTS=$(grep -c "^users " "${PROXY3_CONFIG}.users" || echo 0)
	if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
		exit 1
	fi

	echo ""
	echo "Select the existing client you want to remove"
	until [[ ${CLIENT_NUMBER} -ge 1 && ${CLIENT_NUMBER} -le ${NUMBER_OF_CLIENTS} ]]; do
		if [[ ${CLIENT_NUMBER} == '1' ]]; then
			read -rp "Select one client [1]: " CLIENT_NUMBER
		else
			read -rp "Select one client [1-${NUMBER_OF_CLIENTS}]: " CLIENT_NUMBER
		fi
	done

	CLIENT_NAME=$(grep "^users " "${PROXY3_CONFIG}.users" | cut -d' ' -f2 | cut -d':' -f1 | sed -n "${CLIENT_NUMBER}"p)

	sed -i "/^users ${CLIENT_NAME}:/d" "${PROXY3_CONFIG}.users"

	generateConfig

	if systemctl is-active --quiet 3proxy; then
		systemctl restart 3proxy
	fi

	echo ""
	echo -e "${GREEN}Client ${CLIENT_NAME} removed successfully!${NC}"
}

function uninstall3proxy() {
	echo ""
	echo -e "\n${RED}WARNING: This will uninstall 3proxy and remove all the configuration files!${NC}"
	echo -e "${ORANGE}Please backup the ${PROXY3_CONFIG_DIR} directory if you want to keep your configuration files.\n${NC}"
	read -rp "Do you really want to remove 3proxy? [y/n]: " -e REMOVE
	REMOVE=${REMOVE:-n}
	if [[ $REMOVE == 'y' ]]; then
		systemctl stop 3proxy
		systemctl disable 3proxy

		rm -f "${PROXY3_SERVICE}"
		systemctl daemon-reload

		rm -rf "${PROXY3_CONFIG_DIR}"
		rm -f "${PROXY3_BINARY}"

		echo ""
		echo -e "${GREEN}3proxy uninstalled successfully!${NC}"
		exit 0
	else
		echo ""
		echo "Removal aborted!"
	fi
}

function manageMenu() {
	echo "Welcome to 3proxy-install!"
	echo "The git repository is available at: https://github.com/a0s/3proxy-install"
	echo ""
	echo "It looks like 3proxy is already installed."
	echo ""
	echo "What do you want to do?"
	echo "   1) Add a new user"
	echo "   2) Remove existing user"
	echo "   3) Remove 3proxy"
	echo "   4) Exit"
	until [[ ${MENU_OPTION} =~ ^[1-4]$ ]]; do
		read -rp "Select an option [1-4]: " MENU_OPTION
	done
	case "${MENU_OPTION}" in
	1)
		newClient
		;;
	2)
		removeClient
		;;
	3)
		uninstall3proxy
		;;
	4)
		exit 0
		;;
	esac
}

initialCheck

if [[ -e ${PROXY3_PARAMS} ]]; then
	loadParams
	manageMenu
else
	install3proxy
fi

