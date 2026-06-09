#!/bin/bash

# Initial setup requires elevation (run as root or via sudo):
#   sudo bash -c 'source <(curl -s https://raw.githubusercontent.com/Rebellion-Automation/deploy/refs/heads/main/deploy-komodo-v2.sh)'
#
# After creating the service user (su <username>), run without sudo so init can
# clone to /opt/rebellion and cd persists in your shell:
#   source <(curl -s https://raw.githubusercontent.com/Rebellion-Automation/deploy/refs/heads/main/deploy-komodo-v2.sh)

# Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color / Reset

DEPLOY_ROOT="/opt/rebellion"
DEPLOY_DIR="/opt/rebellion/deploy"
WIREGUARD_DIR="${DEPLOY_ROOT}/wireguard"
WIREGUARD_PRIVATE_KEY="${WIREGUARD_DIR}/privatekey"
WIREGUARD_PUBLIC_KEY="${WIREGUARD_DIR}/publickey"
REPO_URL="https://github.com/Rebellion-Automation/deploy.git"
REPO_BRANCH="main"
GITHUB_RAW_URL="https://raw.githubusercontent.com/Rebellion-Automation/deploy/refs/heads/main/deploy-komodo-v2.sh"

WIREGUARD_CONF="/etc/wireguard/wg0.conf"
WIREGUARD_SPOKE_ADDRESS="10.0.0.2/24"
WIREGUARD_HUB_ADDRESS="10.0.0.1/32"
WIREGUARD_HUB_PORT="51820"

_is_sourced() {
	[[ "${BASH_SOURCE[0]}" != "${0}" ]]
}

_safe_exit() {
	local code=${1:-0}
	if _is_sourced; then
		return "$code"
	else
		exit "$code"
	fi
}

_bootstrap_path() {
	realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}"
}

_bootstrap_from_curl() {
	local path
	path=$(_bootstrap_path)
	[[ "$path" == /dev/fd/* || "$path" == /proc/*/fd/* ]]
}

_is_known_flag() {
	case "$1" in
		-h | --help | -p | --install-prerequisites | -a | --add-user | -i | --init)
			return 0
			;;
		*)
			return 1
			;;
	esac
}

_normalize_args() {
	# Sourced scripts inherit the caller's positional parameters; ignore stray
	# values when bootstrapping via curl unless an explicit flag was passed.
	if _is_sourced && _bootstrap_from_curl && [ $# -gt 0 ] && ! _is_known_flag "$1"; then
		set --
	fi
}

_deploy_dir_empty() {
	[ ! -d "$DEPLOY_DIR" ] || [ -z "$(ls -A "$DEPLOY_DIR" 2>/dev/null)" ]
}

_prerequisites_installed() {
	command -v docker &>/dev/null \
		&& command -v git &>/dev/null \
		&& command -v wg &>/dev/null \
		&& systemctl is-active --quiet docker 2>/dev/null
}

_check_docker_accessible() {
	if ! command -v docker &>/dev/null; then
		echo -e "${RED}Docker is not installed. Please run the --install-prerequisites flag to install docker.${NC}"
		return 1
	fi

	if ! docker info &>/dev/null; then
		echo -e "${RED}Docker is installed but not accessible.${NC}"
		echo -e "${YELLOW}The daemon may not be running (check with 'systemctl status docker'), or the current user may lack permission.${NC}"
		echo -e "${YELLOW}If you were recently added to the docker group, log out and back in (or run 'newgrp docker').${NC}"
		echo -e "${YELLOW}Otherwise, run with --add-user to add a user.${NC}"
		return 1
	fi

	return 0
}

_print_bootstrap_cleanup() {
	local bootstrap_path
	bootstrap_path=$(_bootstrap_path)

	if _is_sourced && [[ "$bootstrap_path" == /dev/fd/* || "$bootstrap_path" == /proc/*/fd/* ]]; then
		echo -e "${YELLOW}This script was sourced from curl (no on-disk bootstrap copy).${NC}"
		echo -e "${YELLOW}If you saved a copy elsewhere (e.g. /usr/local/sbin/deploy.sh), remove it with:${NC}"
		echo -e "  rm /path/to/saved/deploy.sh"
	else
		echo -e "${YELLOW}Remove the bootstrap copy with:${NC}"
		echo -e "  rm \"${bootstrap_path}\""
	fi
}

function show_help() {
	echo "╔══════════════════════════════════════════════════════════════════════════════╗"
	echo "║                 Rebellion Komodo Deployment Script Help                      ║"
	echo "╚══════════════════════════════════════════════════════════════════════════════╝"
	echo ""
	echo "Usage:"
	echo "  sudo bash -c 'source <(curl -s ${GITHUB_RAW_URL}) [OPTIONS]'   (initial setup)"
	echo "  source <(curl -s ${GITHUB_RAW_URL}) [OPTIONS]                    (service user)"
	echo "  ${DEPLOY_DIR}/deploy.sh [OPTIONS]                                (after init)"
	echo ""
	echo "  Run elevated with sudo for --install-prerequisites and --add-user."
	echo "  Without flags, missing prerequisites are installed automatically (root only),"
	echo "  then you are prompted to create the service user."
	echo ""
	echo "Setup Options:"
	echo "  -p, --install-prerequisites"
	echo "      Install Docker, git, WireGuard, and enable the Docker service. Requires root."
	echo ""
	echo "  -a, --add-user"
	echo "      Create a dedicated service user with Docker access and ownership of"
	echo "      ${DEPLOY_ROOT}. Requires root."
	echo ""
	echo "  -i, --init"
	echo "      Clone the deployment repository to ${DEPLOY_DIR}, generate a WireGuard"
	echo "      keypair for telemetry, and cd into it. When sourced, the directory"
	echo "      change persists in your shell. During initial sudo setup, you may also"
	echo "      be prompted to write a WireGuard client config to ${WIREGUARD_CONF}."
	echo ""
	echo "General Options:"
	echo "  -h, --help"
	echo "      Show this help message."
	echo ""
	echo "First-time setup (fresh Debian server):"
	echo ""
	echo "  # 1. As root — installs prerequisites, creates the service user, and"
	echo "  #    prompts to clone the repo into ${DEPLOY_DIR}"
	echo "  sudo bash -c 'source <(curl -s ${GITHUB_RAW_URL})'"
	echo ""
	echo "  # 2. If you skipped initialization, switch to the service user and run:"
	echo "  su <username>"
	echo "  source <(curl -s ${GITHUB_RAW_URL})"
	echo ""
	echo "After initialization, run all further commands from ${DEPLOY_DIR}:"
	echo "  cd ${DEPLOY_DIR} && ./deploy.sh [flags]"
	echo ""
}

function install_docker() {
	if [ "$EUID" -ne 0 ]; then
		echo -e "${RED}Please run elevated with sudo.${NC}"
		echo -e "${YELLOW}  sudo bash -c 'source <(curl -s ${GITHUB_RAW_URL}) -p'${NC}"
		_safe_exit 1
	fi

	echo -e "${GREEN}Installing Docker${NC}"
	apt update
	apt install -y ca-certificates curl
	install -m 0755 -d /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
	chmod a+r /etc/apt/keyrings/docker.asc

	tee /etc/apt/sources.list.d/docker.sources <<-EOF
	Types: deb
	URIs: https://download.docker.com/linux/debian
	Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
	Components: stable
	Architectures: $(dpkg --print-architecture)
	Signed-By: /etc/apt/keyrings/docker.asc
	EOF

	apt update
	apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

	systemctl start docker
	systemctl enable docker

	apt install -y git wireguard
	echo -e "${GREEN}Git and WireGuard installed successfully.${NC}"

	echo -e "Do you want to add the current user to the docker group? (y/n)"
	echo -e "If you want a dedicated service user instead, select no — you will be prompted to create one next."
	read -p "(Y/N) " add_current_user
	if [[ "$add_current_user" =~ ^[Yy]$ ]]; then
		target_user="${SUDO_USER:-$USER}"
		if [ -z "$target_user" ] || [ "$target_user" = "root" ]; then
			echo -e "${RED}Could not determine the user to add. Run this script with sudo as a non-root user.${NC}"
			_safe_exit 1
		fi
		if ! getent group docker &>/dev/null; then
			groupadd docker
		fi
		usermod -aG docker "$target_user"
		echo -e "${GREEN}User $target_user has been added to the docker group.${NC}"
		echo -e "${YELLOW}Log out and back in (or run 'newgrp docker') for group membership to take effect.${NC}"
	else
		echo -e "${YELLOW}No user was added to the docker group.${NC}"
	fi
}

_prompt_add_service_user() {
	if [ "$EUID" -ne 0 ]; then
		return 0
	fi

	echo ""
	echo -e "Do you want to create the service user now? (Y/n)"
	echo -e "The service user will own ${DEPLOY_ROOT} and run deployments."
	read -p "Choice: " create_service_user
	if [[ ! "$create_service_user" =~ ^[Nn]$ ]]; then
		add_user
	else
		echo -e "${YELLOW}Skipped service user creation.${NC}"
		echo -e "${YELLOW}Create one later with:${NC}"
		echo -e "  sudo bash -c 'source <(curl -s ${GITHUB_RAW_URL}) -a'"
	fi
}

_print_subsequent_run_note() {
	local username=$1

	echo ""
	echo -e "${YELLOW}Note:${NC} You are still running as root. For any subsequent script runs, switch to the service user first:"
	echo -e "  su ${username}"
	echo -e "  cd ${DEPLOY_DIR} && ./deploy.sh [flags]"
}

_run_init_as_user() {
	local username=$1
	echo -e "${GREEN}Initializing deployment as ${username}...${NC}"
	if su - "$username" -c "source <(curl -s ${GITHUB_RAW_URL})"; then
		_prompt_wireguard_config
		_print_subsequent_run_note "$username"
	else
		echo -e "${RED}Initialization failed.${NC}"
		return 1
	fi
}

_prompt_init_deployment() {
	local username=$1

	echo ""
	echo -e "Initialize deployment now? (clone repo to ${DEPLOY_DIR}) (Y/n)"
	read -p "Choice: " do_init
	if [[ "$do_init" =~ ^[Nn]$ ]]; then
		echo -e "${YELLOW}Skipped initialization.${NC}"
		echo -e "${BLUE}Next steps:${NC}"
		echo -e "  su ${username}"
		echo -e "  source <(curl -s ${GITHUB_RAW_URL})"
		return 0
	fi

	_run_init_as_user "$username"
}

function add_user() {
	if [ "$EUID" -ne 0 ]; then
		echo -e "${RED}Please run elevated with sudo.${NC}"
		echo -e "${YELLOW}  sudo bash -c 'source <(curl -s ${GITHUB_RAW_URL}) -a'${NC}"
		_safe_exit 1
	fi

	if ! command -v docker &>/dev/null; then
		echo -e "${RED}Docker is not installed. Please run the --install-prerequisites flag to install docker.${NC}"
		_safe_exit 1
	fi

	read -p "Enter the username for the service user. This user will own ${DEPLOY_ROOT}: " username
	if [ -z "$username" ]; then
		echo -e "${RED}Username cannot be empty.${NC}"
		_safe_exit 1
	fi

	if id "$username" &>/dev/null; then
		echo -e "${RED}User $username already exists.${NC}"
		_safe_exit 1
	fi

	password_set=false
	while [ "$password_set" = false ]; do
		read -s -p "Enter the password for the user: " password
		echo
		read -s -p "Confirm the password: " password_confirm
		echo

		if [ "$password" != "$password_confirm" ]; then
			echo -e "${RED}Passwords do not match. Please try again.${NC}"
			continue
		fi

		useradd -m -s /bin/bash "$username"
		echo "$username:$password" | chpasswd
		if [ $? -ne 0 ]; then
			echo -e "${RED}Failed to set password for $username.${NC}"
			userdel -r "$username" 2>/dev/null || true
			_safe_exit 1
		fi

		password_set=true
	done

	if ! getent group docker &>/dev/null; then
		groupadd docker
	fi

	usermod -aG docker "$username"

	mkdir -p "$DEPLOY_ROOT"
	chown "$username:$username" "$DEPLOY_ROOT"
	chmod 755 "$DEPLOY_ROOT"

	echo -e "${GREEN}User $username has been created and added to the docker group.${NC}"
	echo -e "${GREEN}${DEPLOY_ROOT} is owned by $username.${NC}"
	_prompt_init_deployment "$username"
}

_generate_wireguard_keys() {
	if ! command -v wg &>/dev/null; then
		echo -e "${RED}WireGuard is not installed. Please run the --install-prerequisites flag first.${NC}"
		_safe_exit 1
	fi

	if [ -f "$WIREGUARD_PRIVATE_KEY" ] && [ -f "$WIREGUARD_PUBLIC_KEY" ]; then
		echo -e "${YELLOW}WireGuard keys already exist at ${WIREGUARD_DIR}.${NC}"
		echo -e "${GREEN}Public key (register on telemetry ingester):${NC}"
		cat "$WIREGUARD_PUBLIC_KEY"
		return 0
	fi

	if ! mkdir -p "$WIREGUARD_DIR" 2>/dev/null; then
		echo -e "${RED}Failed to create ${WIREGUARD_DIR}.${NC}"
		echo -e "${YELLOW}Ensure you are running as the service user who owns ${DEPLOY_ROOT}.${NC}"
		_safe_exit 1
	fi

	local private_key public_key
	private_key=$(wg genkey)
	public_key=$(echo "$private_key" | wg pubkey)

	umask 077
	echo "$private_key" > "$WIREGUARD_PRIVATE_KEY"
	umask 022
	echo "$public_key" > "$WIREGUARD_PUBLIC_KEY"
	chmod 600 "$WIREGUARD_PRIVATE_KEY"
	chmod 644 "$WIREGUARD_PUBLIC_KEY"

	echo -e "${GREEN}WireGuard keypair generated at ${WIREGUARD_DIR}${NC}"
	echo -e "${YELLOW}Provide this public key to the telemetry ingester administrator:${NC}"
	echo "$public_key"
	echo -e "${YELLOW}Private key stored at ${WIREGUARD_PRIVATE_KEY} (keep secret).${NC}"
}

_prompt_wireguard_config() {
	if [ "$EUID" -ne 0 ]; then
		return 0
	fi

	if [ ! -f "$WIREGUARD_PRIVATE_KEY" ]; then
		echo -e "${YELLOW}WireGuard private key not found at ${WIREGUARD_PRIVATE_KEY}; skipping client configuration.${NC}"
		return 0
	fi

	if [ -f "$WIREGUARD_CONF" ]; then
		echo -e "${YELLOW}WireGuard configuration already exists at ${WIREGUARD_CONF}.${NC}"
		return 0
	fi

	echo ""
	echo -e "Initialize WireGuard client configuration at ${WIREGUARD_CONF}? (y/n)"
	read -p "(Y/N) " init_wg
	if [[ ! "$init_wg" =~ ^[Yy]$ ]]; then
		echo -e "${YELLOW}Skipped WireGuard client configuration.${NC}"
		return 0
	fi

	local hub_public_key hub_endpoint private_key
	read -p "Enter the hub public key (HUB_PUBLIC_KEY): " hub_public_key
	if [ -z "$hub_public_key" ]; then
		echo -e "${RED}Hub public key cannot be empty.${NC}"
		return 1
	fi

	read -p "Enter the hub public IP or domain (HUB_PUBLIC_IP): " hub_endpoint
	if [ -z "$hub_endpoint" ]; then
		echo -e "${RED}Hub endpoint cannot be empty.${NC}"
		return 1
	fi

	private_key=$(cat "$WIREGUARD_PRIVATE_KEY")

	install -m 0755 -d /etc/wireguard
	umask 077
	cat > "$WIREGUARD_CONF" <<EOF
[Interface]
PrivateKey = ${private_key}
Address = ${WIREGUARD_SPOKE_ADDRESS}

[Peer]
PublicKey = ${hub_public_key}
AllowedIPs = ${WIREGUARD_HUB_ADDRESS}
Endpoint = ${hub_endpoint}:${WIREGUARD_HUB_PORT}
PersistentKeepalive = 25
EOF
	chmod 600 "$WIREGUARD_CONF"
	umask 022

	echo -e "${GREEN}WireGuard configuration written to ${WIREGUARD_CONF}${NC}"
	echo -e "${YELLOW}Enable the tunnel with: systemctl enable --now wg-quick@wg0${NC}"
}

function init_deployment() {
	if ! command -v git &>/dev/null; then
		echo -e "${RED}Git is not installed. Please run the --install-prerequisites flag first.${NC}"
		_safe_exit 1
	fi

	if ! _check_docker_accessible; then
		_safe_exit 1
	fi

	if [ -d "$DEPLOY_DIR" ] && [ -n "$(ls -A "$DEPLOY_DIR" 2>/dev/null)" ]; then
		echo -e "${RED}${DEPLOY_DIR} already exists and is not empty.${NC}"
		echo -e "${YELLOW}Run commands from the existing deployment directory instead:${NC}"
		echo -e "  cd ${DEPLOY_DIR} && ./deploy.sh --help"
		_safe_exit 1
	fi

	if [ -d "$DEPLOY_ROOT" ]; then
		deploy_root_owner=$(stat -c '%U' "$DEPLOY_ROOT" 2>/dev/null || echo "")
		if [ -n "$deploy_root_owner" ] && [ "$deploy_root_owner" != "$USER" ]; then
			echo -e "${YELLOW}Warning: ${DEPLOY_ROOT} is owned by ${deploy_root_owner}, not ${USER}.${NC}"
			echo -e "${YELLOW}Run this step as the service user: su ${deploy_root_owner}${NC}"
		fi
	fi

	if ! mkdir -p "$DEPLOY_DIR" 2>/dev/null; then
		echo -e "${RED}Failed to create ${DEPLOY_DIR}.${NC}"
		echo -e "${YELLOW}Ensure you are running as the service user who owns ${DEPLOY_ROOT}.${NC}"
		_safe_exit 1
	fi

	echo -e "${GREEN}Cloning repository to ${DEPLOY_DIR}...${NC}"
	if ! git clone --branch "$REPO_BRANCH" "$REPO_URL" "$DEPLOY_DIR"; then
		echo -e "${RED}Failed to clone repository.${NC}"
		rmdir "$DEPLOY_DIR" 2>/dev/null || true
		_safe_exit 1
	fi

	cd "$DEPLOY_DIR" || _safe_exit 1

	echo -e "${GREEN}Repository cloned to: ${DEPLOY_DIR}${NC}"
	echo -e "${GREEN}Working directory is now: $(pwd)${NC}"
	echo ""
	_generate_wireguard_keys
	if [ "$EUID" -eq 0 ]; then
		_prompt_wireguard_config
	fi
	echo ""
	_print_bootstrap_cleanup
	echo ""
	echo -e "${BLUE}Further usage must be run from the shared directory:${NC}"
	echo -e "  cd ${DEPLOY_DIR} && ./deploy.sh [flags]"
	echo ""
	echo -e "${BLUE}Example:${NC}"
	echo -e "  ./deploy.sh --help"
}

_handle_no_args() {
	local prereqs_just_installed=false

	if ! _prerequisites_installed; then
		if [ "$EUID" -ne 0 ]; then
			echo -e "${RED}Prerequisites are not installed.${NC}"
			echo -e "${YELLOW}Run elevated with sudo:${NC}"
			echo -e "  sudo bash -c 'source <(curl -s ${GITHUB_RAW_URL})'"
			_safe_exit 1
		fi
		echo -e "${YELLOW}Prerequisites not found. Installing automatically...${NC}"
		install_docker
		prereqs_just_installed=true
	fi

	if [ "$EUID" -eq 0 ]; then
		if [ "$prereqs_just_installed" = true ]; then
			echo -e "${GREEN}Prerequisites installed successfully.${NC}"
			_prompt_add_service_user
		else
			echo -e "${GREEN}Prerequisites are already installed.${NC}"
			echo -e "${BLUE}Next step — switch to the service user, or create one with:${NC}"
			echo -e "  sudo bash -c 'source <(curl -s ${GITHUB_RAW_URL}) -a'"
		fi
		return 0
	fi

	if _deploy_dir_empty; then
		init_deployment
	else
		show_help
	fi
}

_normalize_args "$@"

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
	show_help
	_safe_exit 0
fi

if [ "$1" = "--install-prerequisites" ] || [ "$1" = "-p" ]; then
	install_docker
	_prompt_add_service_user
	_safe_exit 0
fi

if [ "$1" = "--add-user" ] || [ "$1" = "-a" ]; then
	add_user
	_safe_exit 0
fi

if [ "$1" = "--init" ] || [ "$1" = "-i" ]; then
	init_deployment
	_safe_exit 0
fi

if [ -z "$1" ]; then
	_handle_no_args
	_safe_exit 0
fi

# After initial setup, show help instead of erroring on stray arguments.
if [ -d "$DEPLOY_DIR" ] && [ -n "$(ls -A "$DEPLOY_DIR" 2>/dev/null)" ]; then
	show_help
	_safe_exit 0
fi

if [ "$EUID" -eq 0 ] && _prerequisites_installed; then
	_handle_no_args
	_safe_exit 0
fi

echo -e "${RED}Unknown option: $1${NC}"
echo -e "${YELLOW}Run with --help for usage.${NC}"
_safe_exit 1
