function show_help() {

}
function update_repo() {
	git pull origin main
}
function install_prerequisites() {
	# Check if this is run with sudo, if not, exit with error
	if [ "$EUID" -ne 0 ]; then
		echo "Please run this script with sudo."
		exit 1
	fi
	
	# Prerequisite installation:
	# 1. Just in case any alternate docker installation is used, remove it first.
	apt remove -y $(dpkg --get-selections docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc | cut -f1) 2>/dev/null || true

	# 2. Install Docker
	# Add Docker's official GPG key:
	apt update -y
	apt install -y ca-certificates curl
	install -m 0755 -d /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
	chmod a+r /etc/apt/keyrings/docker.asc

	# Add the repository to Apt sources:
	tee /etc/apt/sources.list.d/docker.sources <<-EOF
	Types: deb
	URIs: https://download.docker.com/linux/ubuntu
	Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
	Components: stable
	Signed-By: /etc/apt/keyrings/docker.asc
	EOF

	sudo apt update -y

	# Install docker engine, docker CLI, containerd, docker buildx, docker compose
	sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

	# Start and enable Docker service
	systemctl start docker
	systemctl enable docker

	# Wait a moment for Docker daemon to fully start
	sleep 2

	# Implement user access controls, add user to docker group
	sudo usermod -aG docker $SUDO_USER

	# Test docker installation (using sudo since group change requires new session)
	sudo docker run hello-world

	# If docker hello-world fails, exit with error
	if [ $? -ne 0 ]; then
		echo "Docker installation failed. Please check the logs and try again."
		exit 1
	fi

	sudo apt install -y git
}
function add_user() {
	# Make sure script is run with sudo
	if [ "$EUID" -ne 0 ]; then
		echo "Please run this script with sudo."
		exit 1
	fi
	# Set up a user to run docker commands and git without sudo
	echo "Setting up a user to run docker commands and git without sudo"
	read -p "Enter the username to set up: " username

	# Check if user exists, if not create it
	if id "$username" &>/dev/null; then
		echo "User $username already exists."
		exit 1
	else
		# Create the user with a home directory
		useradd -m -s /bin/bash "$username"
		echo "User $username has been created."
	fi

	# Set a password for the user (with retry on failure)
	# TODO: Add a password dictionary check or parse output of chpasswd to check real strength
	password_set=false
	while [ "$password_set" = false ]; do
		read -s -p "Enter the password for the user: " password
		echo  # Add a newline after the hidden input
		
		# Validate password strength
		password_valid=true
		error_msg=""
		
		# Check minimum length (8 characters)
		if [ ${#password} -lt 8 ]; then
			password_valid=false
			error_msg="Password must be at least 8 characters long."
		fi
		
		# Check for uppercase letter
		if [ "$password_valid" = true ] && ! echo "$password" | grep -q '[A-Z]'; then
			password_valid=false
			error_msg="Password must contain at least one uppercase letter."
		fi
		
		# Check for lowercase letter
		if [ "$password_valid" = true ] && ! echo "$password" | grep -q '[a-z]'; then
			password_valid=false
			error_msg="Password must contain at least one lowercase letter."
		fi
		
		# Check for number
		if [ "$password_valid" = true ] && ! echo "$password" | grep -q '[0-9]'; then
			password_valid=false
			error_msg="Password must contain at least one number."
		fi
		
		# If validation fails, show error and retry
		if [ "$password_valid" = false ]; then
			echo "Password does not meet requirements: $error_msg"
			echo "Please try again."
			continue
		fi
		
		# If validation passes, attempt to set the password
		echo "$username:$password" | chpasswd
		if [ $? -eq 0 ]; then
			echo "Password for $username has been set successfully."
			password_set=true
		else
			echo "Failed to set password. Please try again."
		fi
	done

	# If the docker group does not exist, create it
	if ! getent group docker &>/dev/null; then
		sudo groupadd docker
	fi

	# Add the user to the docker group
	sudo usermod -aG docker "$username"
	echo "User $username has been added to the docker group."

	# Note: git group is not necessary for git operations, so we skip it

	# Clone the repo in the new user's home directory
	git clone github.com/Rebellion-Automation/deploy ~$username/.rebellion
	echo "Repo cloned successfully in ~$username/.rebellion"

	# Prompt the user to remove the script from the current directory. Only one instance of the script should exist in the system.
	echo "Please run 'su $username' to switch to the new user and run deploy-komodo.sh from the new user's home directory at ~/.rebellion/deploy/deploy-komodo.sh."
	echo "Further usage of this script will need to be performed from this location."
	read -p "Would you like to remove the script from the current directory? (recommended) (y/n) " REMOVE_SCRIPT
	if [[ "$REMOVE_SCRIPT" = "y" || "$REMOVE_SCRIPT" = "Y" ]]; then
		rm -- "$0"
		echo "Script removed successfully."
	else
		echo "Script not removed."
	fi
	exit 0
}
function core_init() {
	echo "Initializing deployment of Komodo Core"
	echo "Present working directory: $PWD"

	# Confirm the present working directory with the user
	echo "You are about to deploy Komodo Core in this directory: $PWD/Komodo"
	read -p "Is this the correct directory? (y/n): " CONFIRM_PWD
	if [[ "$CONFIRM_PWD" != "y" && "$CONFIRM_PWD" != "Y" ]]; then
		echo "Aborting deployment. Please run this script from the desired directory."
		exit 1
	fi

	# Create the komodo directory if it doesn't exist
	if [ ! -d "Komodo" ]; then
		mkdir -p "Komodo"
	fi

	# Create the caddy directory if it doesn't exist
	if [ ! -d "Komodo/caddy" ]; then
		mkdir -p "Komodo/caddy"
	fi

	# Prompt the user for the following:
	# Domain in format of subdomain.domain.com, ensure there is an A record pointing to this server's IP address
	echo "Please note for functional SSL certificate generation, your subdomain must have an A record pointing to this server's IP address."
	echo "Certificate generation will be performed automatically by Caddy and Let's Encrypt."
	read -p "Enter your domain (format: subdomain.domain.com): " DOMAIN

	# Generate a caddyfile for the domain
	cat <<-EOF > "Komodo/caddy/Caddyfile"
	$DOMAIN {
		reverse_proxy core:9120
		}
	EOF

	echo "Caddyfile generated successfully in $PWD/Komodo/caddy/Caddyfile"

	# TODO: Copy the .env.core.template to .env
	cp TEMPLATES/KomodoCompose/.env.core.template Komodo/.env.core
	echo "Environment file generated successfully in $PWD/.env.core"

	PASSKEY=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32; echo)
	echo "Passkey generated successfully: $PASSKEY"
	echo "Periphery node will need this same passkey to authenticate with the core node."

	# Replace the passkey in the environment file
	# TODO: Test and ensure these both work
	sed -i "s/KOMODO_CORE_PASSKEY=/KOMODO_CORE_PASSKEY=$PASSKEY/" Komodo/.env.core
	echo "Passkey replaced successfully in $PWD/.env.core"

	KOMODO_DB_PASSWORD=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24; echo)
	echo "Database password generated successfully for Komodo Core"

	# Replace the database password in the environment file
	sed -i "s/KOMODO_DB_PASSWORD=/KOMODO_DB_PASSWORD=$KOMODO_DB_PASSWORD/" .env.core
	echo "Database password replaced successfully in $PWD/.env.core"
}
function periphery_init() {
}

# Flag parsing
INSTALL_PREREQS=false
UPDATE_REPO=false
ADD_USER=false

INIT=false

CORE_INIT=false
PERIPHERY_INIT=false


# Parse command line flags
while [[ $# -gt 0 ]]; do
	case $1 in
		--install-prerequisites | -p)
			INSTALL_PREREQS=true
			shift
			;;
		--add-user | -a)
			ADD_USER=true
			shift
			;;
		--update | -u)
			UPDATE_REPO=true
			shift
			;;
		--init | -i)
			INIT=true
			shift
			;;
		-h | --help)
			show_help
			exit 0
			;;
		*)
			echo "Unknown option: $1"
			exit 1
			;;
	esac
done

# Case of init, prompt user for type of initialization
if [ "$INIT" = true ]; then

# Check if the current working directory is a git repo or if the script was curled. If the script was curled, we need to clone the repo.
if [ -d ".git" ]; then
  echo "Pulling latest changes."
  update_repo
else
  echo "Directory is not a git repo. If you added a user account, you may need to run the script from the new user's home directory ~/.rebellion/deploy/deploy-komodo.sh."
  exit 1
fi

  echo "What type of initialization do you want to perform?"
  echo "1. Core"
  echo "2. Periphery"
  read -p "Enter the number of the type of initialization you want to perform: " INIT_TYPE
  if [ "$INIT_TYPE" = "1" ]; then
    CORE_INIT=true
  elif [ "$INIT_TYPE" = "2" ]; then
    PERIPHERY_INIT=true
  fi
  else
    echo "Invalid initialization type. Please enter 1 or 2."
    exit 1
  fi
fi

if [ "$CORE_INIT" = true ]; then
  core_init
fi

if [ "$PERIPHERY_INIT" = true ]; then
  periphery_init
fi

if [ "$INSTALL_PREREQS" = true ]; then
  install_prerequisites
fi

if [ "$UPDATE_REPO" = true ]; then
  update_repo
fi

if [ "$ADD_USER" = true ]; then
  add_user
fi
