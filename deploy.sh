#!/bin/bash

function show_help() {
	echo "Usage: $0 [-flags][arguments]"
	echo ""
	echo "Options:"
	echo "  -p|--install-prerequisites: Install the prerequisites for the deployment. This includes docker and git."
	echo "  -a|--add-user: Add a new least-privileged user account for the deployment. Includes access to docker and git."
	echo "  --username: Your github username. This will be used to pull the docker images from the github container registry."
	echo "  --pat: Your personal access token for the github container registry."
	echo "  -u|--update: Update the repository to the latest version. This will be run automatically on initial deployment."
	echo "  -r|--run [service]: Run a specific service. This will run the docker-compose.yml file with the service name provided."
	echo "  -s|--stop [service]: Stop a specific service. This will stop the docker-compose.yml file with the service name provided."
	echo "  --no-auth: Skip authentication with the github container registry. This is useful for starting the services without updating the docker images."
	echo "  -h: Show this help message"
	exit 0
}

function install_prerequisites() {
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
	sudo usermod -aG docker $USER

	# Test docker installation (using sudo since group change requires new session)
	sudo docker run hello-world

	# If docker hello-world fails, exit with error
	if [ $? -ne 0 ]; then
		echo "Docker installation failed. Please check the logs and try again."
		exit 1
	fi
}

function add_user() {
		# TODO: Add code to handle --add-user flag here
	echo "Add user functionality will be executed here"
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
			shift
			;;
		--pat)
			GITHUB_PAT=$2
			if [ -z "$GITHUB_PAT" ]; then
				echo "Github personal access token is required for the --pat flag"
				exit 1
			fi
			shift
			;;
		--run | -r)
			RUN_SERVICE=true
			SERVICE_NAME=$2
			if [ -z "$SERVICE_NAME" ]; then
				echo "Service name is required for the --run flag"
				exit 1
			fi
			shift
			;;
		--stop | -s)
			STOP_SERVICE=true
			SERVICE_NAME=$2
			if [ -z "$SERVICE_NAME" ]; then
				echo "Service name is required for the --stop flag"
				exit 1
			fi
			shift
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
	exit 0
fi

# Add least-privileged user account if --add-user flag is provided
if [ "$ADD_USER" = true ]; then
	add_user
	exit 0
fi
# Above flags will exit upon completion, remaining code will only be executed if none of the above flags are provided

# Check if docker is installed and running, if not, prompt the user to run the --install-prerequisites flag
if ! docker info &>/dev/null; then
	echo "Docker is not installed or running. Please run the --install-prerequisites flag to install docker."
	exit 1
fi
# Check if git is installed, if not, prompt the user to run the --install-prerequisites flag
if ! git --version &>/dev/null; then
	echo "Git is not installed. Please run the --install-prerequisites flag to install git."
	exit 1
fi

# Update the repository if --update flag is provided, if the directory does not exist, or if the directory is empty
if [ "$UPDATE_REPO" = true | ! -d /home/$USER/.rebellion | [ -z "$(ls -A /home/$USER/.rebellion)" ] ]; then
	# Set up .rebellion directory in the current user's home directory
	# If the directiory already exists, it will not be overwritten
	mkdir -p /home/$USER/.rebellion
	# Case: Directory does not exist or is empty
	if [ ! -d /home/$USER/.rebellion  | [ -z "$(ls -A /home/$USER/.rebellion)" ] ]; then
		echo "Directory does not exist or is empty, creating directory and cloning repository"
		git clone https://github.com/Rebellion-Automation/deploy.git /home/$USER/.rebellion
	fi
	# Case: Git repository has been cloned already, pull the latest changes
	if [ -d /home/$USER/.rebellion/.git ]; then
		# Backup previous configuration to the backups/ directory, directory will be tagged with the current date and time
		BACKUP_DATE_TAG=$(date +%Y-%m-%d_%H-%M-%S)
		mkdir -p /home/$USER/.rebellion/backups/$BACKUP_DATE_TAG
		cp -r /home/$USER/.rebellion/docker-compose.*.yml /home/$USER/.rebellion/backups/$BACKUP_DATE_TAG/

		# Pull the latest changes from the repository
		git -C /home/$USER/.rebellion pull
		echo "Repository updated successfully. Machine specific docker-compose modifications may have to be performed manually if updated on remote."

		# Cross reference the previous configuration with the new configuration to identify changes. Perform this for all files.
		for file in /home/$USER/.rebellion/; do
			diff -u $file /home/$USER/.rebellion/backups/$BACKUP_DATE_TAG/$file
			# If the files are the same, remove the backup file
			if [ $? -eq 0 ]; then
				rm -f /home/$USER/.rebellion/backups/$BACKUP_DATE_TAG/$file
			fi
			# If the backup directory is empty, remove it to keep the backups directory clean
			if [ -z "$(ls -A /home/$USER/.rebellion/backups/$BACKUP_DATE_TAG)" ]; then
				rm -rf /home/$USER/.rebellion/backups/$BACKUP_DATE_TAG
			fi
		done
	fi
fi

# If the run flag is provided, run the specified service (specified by docker-compose.[service].yml)
if [ "$RUN_SERVICE" = true ]; then
	# Authenticate with the github container registry if --no-auth flag is not provided
	if [ "$NO_AUTH" = false ]; then
		if ! docker login -u $GITHUB_USERNAME -p $GITHUB_PAT ghcr.io; then
			echo "Failed to authenticate with the github container registry"
			exit 1
		fi
	fi
	# The postgres service needs a volume to persist data, so we need to create the volume if it does not exist
	if [ "$SERVICE_NAME" = "postgres" ]; then
		if ! docker volume create postgres_data; then
			echo "Failed to create postgres volume"
			exit 1
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