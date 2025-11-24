#!/bin/bash

function show_help() {
	echo "╔══════════════════════════════════════════════════════════════════════════════╗"
	echo "║                    Rebellion Deployment Script Help                          ║"
	echo "╚══════════════════════════════════════════════════════════════════════════════╝"
	echo ""
	echo "Usage:"
	echo "  $0 [OPTIONS]"
	echo ""
	echo "Setup Options:"
	echo "  -p, --install-prerequisites"
	echo "      Install the prerequisites for the deployment."
	echo "      This includes docker and git."
	echo ""
	echo "  -a, --add-user"
	echo "      Add a new least-privileged user account for the deployment."
	echo "      Includes access to docker and git."
	echo ""
	echo "Authentication Options:"
	echo "  --username USERNAME"
	echo "      Your GitHub username. This will be used to pull the docker images"
	echo "      from the GitHub container registry."
	echo ""
	echo "  --pat TOKEN"
	echo "      Your personal access token for the GitHub container registry."
	echo ""
	echo "  --no-auth"
	echo "      Skip authentication with the GitHub container registry."
	echo "      This is useful for starting the services without updating the"
	echo "      docker images, or if authentication has already been performed."
	echo ""
	echo "Service Management Options:"
	echo "  -r, --run SERVICE"
	echo "      Run a specific service. This will run the docker-compose.yml file"
	echo "      with the service name provided."
	echo ""
	echo "  -s, --stop SERVICE"
	echo "      Stop a specific service. This will stop the docker-compose.yml file"
	echo "      with the service name provided."
	echo ""
	echo "Repository Options:"
	echo "  -u, --update"
	echo "      Update the repository to the latest version."
	echo "      This will be run automatically on initial deployment."
	echo ""
	echo "General Options:"
	echo "  -h, --help"
	echo "      Show this help message."
	echo ""
	echo "Examples:"
	echo "  $0 --install-prerequisites"
	echo "  $0 --add-user"
	echo "  $0 --username myuser --pat mytoken --run api"
	echo "  $0 --run api --no-auth"
	echo "  $0 --stop frontend"
	echo ""
	exit 0
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
}

function add_user() {
	# Set up a user to run docker commands and git without sudo
	echo "Setting up a user to run docker commands and git without sudo"
	read -p "Enter the username to set up: " username

	# Check if user exists, if not create it
	if id "$username" &>/dev/null; then
		echo "User $username already exists."
	else
		# Create the user with a home directory
		useradd -m -s /bin/bash "$username"
		echo "User $username has been created."
	fi

	# Make sure script is run with sudo
	if [ "$EUID" -ne 0 ]; then
		echo "Please run this script with sudo."
		exit 1
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

	echo "Please run 'su $username' to switch to the new user and run deploy.sh."
	exit 0
}

# Initialize flag variable
GITHUB_USERNAME=""
GITHUB_PAT=""
ADD_USER=false
INSTALL_PREREQUISITES=false
UPDATE_REPO=false
RUN_SERVICE=false
STOP_SERVICE=false
SERVICE_NAME=""
NO_AUTH=false

# Parse command line flags
while [[ $# -gt 0 ]]; do
	case $1 in
		--install-prerequisites | -p)
			INSTALL_PREREQUISITES=true
			shift
			;;
		--add-user | -a)
			ADD_USER=true
			shift
			;;
		--username)
			GITHUB_USERNAME=$2
			if [ -z "$GITHUB_USERNAME" ]; then
				echo "Github username is required for the --username flag"
				exit 1
			fi
			shift 2
			;;
		--pat)
			GITHUB_PAT=$2
			if [ -z "$GITHUB_PAT" ]; then
				echo "Github personal access token is required for the --pat flag"
				exit 1
			fi
			shift 2
			;;
		--run | -r)
			RUN_SERVICE=true
			SERVICE_NAME=$2
			if [ -z "$SERVICE_NAME" ]; then
				echo "Service name is required for the --run flag"
				exit 1
			fi
			shift 2
			;;
		--stop | -s)
			STOP_SERVICE=true
			SERVICE_NAME=$2
			if [ -z "$SERVICE_NAME" ]; then
				echo "Service name is required for the --stop flag"
				exit 1
			fi
			shift 2
			;;
		--no-auth)
			NO_AUTH=true
			shift
			;;
		--update | -u)
			UPDATE_REPO=true
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

# Install prerequisites if --install-prerequisites flag is provided
if [ "$INSTALL_PREREQUISITES" = true ]; then
	install_prerequisites
	echo "Prerequisites installed successfully. If a new user account needs to be added, run the --add-user flag."
	echo "Please note that docker installation requires a new session to reload the group permissions."
	echo "If you are ready to deploy the services on the $USER account, run with --update and --run <service>"
	exit 0
fi

# Add least-privileged user account if --add-user flag is provided
if [ "$ADD_USER" = true ]; then
	add_user
	exit 0
fi
# Above flags will exit upon completion, remaining code will only be executed if none of the above flags are provided

# Check if docker is installed and running, if not, prompt the user to run the --install-prerequisites flag
if ! command -v docker &>/dev/null; then
	echo "Docker is not installed. Please run the --install-prerequisites flag to install docker."
	exit 1
fi

# Check if docker daemon is running and accessible
if ! docker info &>/dev/null; then
	echo "Docker daemon is not running or not accessible. Please ensure Docker is running and you have permission to access it."
	echo "You may need to:"
	echo "  1. Start Docker (e.g., 'sudo systemctl start docker' on Linux)"
	echo "  2. Add your user to the docker group (e.g., 'sudo usermod -aG docker $USER' on Linux)"
	echo "  3. Run this script with appropriate permissions"
	exit 1
fi
# Check if git is installed, if not, prompt the user to run the --install-prerequisites flag
if ! git --version &>/dev/null; then
	echo "Git is not installed. Please run the --install-prerequisites flag to install git."
	exit 1
fi

# Update the repository if --update flag is provided, if the directory does not exist, or if the directory is empty
if [ "$UPDATE_REPO" = true ] || [ ! -d /home/$USER/.rebellion ] || [ -z "$(ls -A /home/$USER/.rebellion)" ]; then
	# Set up .rebellion directory in the current user's home directory
	# If the directiory already exists, it will not be overwritten
	mkdir -p /home/$USER/.rebellion
	
	# Check if this is a fresh clone or an update
	WAS_ALREADY_CLONED=false
	if [ -d /home/$USER/.rebellion/.git ]; then
		WAS_ALREADY_CLONED=true
	fi
	
	# Case: Directory does not exist or is empty
	if [ ! -d /home/$USER/.rebellion ] || [ -z "$(ls -A /home/$USER/.rebellion)" ]; then
		echo "Directory does not exist or is empty, creating directory and cloning repository"
		git clone https://github.com/Rebellion-Automation/deploy.git /home/$USER/.rebellion
		
		# Copy .env.template to .env if template exists and .env doesn't exist
		if [ -f /home/$USER/.rebellion/.env.template ] && [ ! -f /home/$USER/.rebellion/.env ]; then
			cp /home/$USER/.rebellion/.env.template /home/$USER/.rebellion/.env
			echo "Created .env file from .env.template"
		fi
	fi
	# Case: Git repository has been cloned already (before this run), pull the latest changes
	if [ "$WAS_ALREADY_CLONED" = true ] && [ -d /home/$USER/.rebellion/.git ]; then
		# Check if there are any changes to pull before backing up
		git -C /home/$USER/.rebellion fetch origin
		LOCAL=$(git -C /home/$USER/.rebellion rev-parse HEAD)
		REMOTE=$(git -C /home/$USER/.rebellion rev-parse origin/main 2>/dev/null || git -C /home/$USER/.rebellion rev-parse @{u} 2>/dev/null)
		
		if [ -z "$REMOTE" ] || [ "$LOCAL" = "$REMOTE" ]; then
			echo "Already up to date."
		else
			# Backup previous configuration to the backups/ directory, directory will be tagged with the current date and time
			BACKUP_DATE_TAG=$(date +%Y-%m-%d_%H-%M-%S)
			mkdir -p /home/$USER/.rebellion/backups/$BACKUP_DATE_TAG
			
			# Backup all docker-compose files
			for file in /home/$USER/.rebellion/docker-compose.*.yml; do
				if [ -f "$file" ]; then
					cp "$file" /home/$USER/.rebellion/backups/$BACKUP_DATE_TAG/
				fi
			done
			
			# Backup .env file if it exists (to preserve user configuration)
			ENV_BACKED_UP=false
			if [ -f /home/$USER/.rebellion/.env ]; then
				cp /home/$USER/.rebellion/.env /home/$USER/.rebellion/backups/$BACKUP_DATE_TAG/.env
				ENV_BACKED_UP=true
			fi

			# Force overwrite local changes with the latest changes from the repository
			# This is safe because we've already backed up the local files above
			git -C /home/$USER/.rebellion reset --hard origin/main
			
			# Restore .env file if it was backed up (preserve user configuration)
			if [ "$ENV_BACKED_UP" = true ]; then
				cp /home/$USER/.rebellion/backups/$BACKUP_DATE_TAG/.env /home/$USER/.rebellion/.env
			fi

			echo "Repository updated successfully. Machine specific docker-compose modifications may have to be performed manually if updated on remote."

			# Cross reference the previous configuration with the new configuration to identify changes. Perform this for all files.
			for file in /home/$USER/.rebellion/backups/$BACKUP_DATE_TAG/docker-compose.*.yml; do
				if [ -f "$file" ]; then
					# Get the filename without the backup directory path
					filename=$(basename "$file")
					current_file="/home/$USER/.rebellion/$filename"
					
					# Compare the backup with the current file
					if [ -f "$current_file" ]; then
						diff -u "$file" "$current_file" > /dev/null 2>&1
						# If the files are the same (diff returns 0), remove the backup file
						if [ $? -eq 0 ]; then
							rm -f "$file"
						fi
					fi
				fi
			done
			
			# If the backup directory is empty, remove it to keep the backups directory clean
			if [ -z "$(ls -A /home/$USER/.rebellion/backups/$BACKUP_DATE_TAG 2>/dev/null)" ]; then
				rm -rf /home/$USER/.rebellion/backups/$BACKUP_DATE_TAG
			fi
		fi
	fi
fi

# If the run flag is provided, run the specified service (specified by docker-compose.[service].yml)
if [ "$RUN_SERVICE" = true ]; then
	# Authenticate with the github container registry if --no-auth flag is not provided
	if [ "$NO_AUTH" = false ]; then
		if ! echo "$GITHUB_PAT" | docker login -u $GITHUB_USERNAME --password-stdin ghcr.io; then
			echo "Failed to authenticate with the github container registry"
			exit 1
		fi
	fi
	# The postgres service needs a volume to persist data, so we need to create the volume if it does not exist
	if [ "$SERVICE_NAME" = "postgres" ]; then
		if ! docker volume inspect xnav_pg_data &>/dev/null; then
			if ! docker volume create xnav_pg_data; then
				echo "Failed to create postgres volume"
				exit 1
			fi
			echo "Created postgres volume xnav_pg_data"
		else
			echo "Postgres volume xnav_pg_data already exists"
		fi
	fi
	docker compose -f /home/$USER/.rebellion/docker-compose.$SERVICE_NAME.yml up -d
	exit 0
fi

# If the stop flag is provided, stop the specified service (specified by docker-compose.[service].yml)
if [ "$STOP_SERVICE" = true ]; then
	docker compose -f /home/$USER/.rebellion/docker-compose.$SERVICE_NAME.yml down
	exit 0
fi