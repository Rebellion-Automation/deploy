# Deployment Instructions

## Easy deployment

### Prerequsite setup
Using a user account with sudo permissions on a fresh install of Ubuntu Server (or debian-like server distro) run this command from a preferred working directory to download the setup script and install prerequisites. Alternatively, local media may be used. Please note that the deploy script can be initially run from any directory, and further installation will be performed in the current active user's `/home` directory. Note that the directories and env files are hidden by default, so use the `-a` flag when performing operations like `ls`

For initial setup with the intent of using a new account with fine-tuned access controls, it is highly recommended to download the script to a directory accessible to all users, such as `/usr/local/sbin`.
```
curl -O [/usr/local/sbin] https://raw.githubusercontent.com/Rebellion-Automation/deploy/refs/heads/main/deploy.sh

chmod +x deploy.sh

sudo ./deploy.sh -p

exit
```
Use `exit` to re-log and reload group changes. After logging back in, the user will be an active member of the docker group. 

### User access controls
If it is determined that a least-privileged user needs to be set up for fine-tuned access controls, run the below commands to create a new user account and switch to it.
```
sudo ./deploy.sh --add-user

su [user]
```
Any subsequent commands no longer require sudo, and this user does not need to be in the sudoers list. 

### Set up deployment directory

After switching to the desired active user account, running the deploy script with no flags will initialize the docker configuration in the user's `/home` directory.

```
./deploy.sh

cd ~/.rebellion
```

**Note:** The deploy script will now live in the user's `./rebellion` directory. Any further usage of this script will need to be performed from this location.

### Environment setup

When the repository is first cloned, the `.template.env` file will be copied to `.env`. This file needs to be updated with actual production environment variables. This is easiest done with `nano .env`.

If needed, individual docker-compose files can be modified to suit each deployment. For instance, if multiple API instances need to be run at once, another instance can be defined in `docker-compose.api.yml`.

### Authenticate with GHCR

Authentication can be performed separately with 
```
docker login ghcr.io
```
This uses the interactive docker login. `deploy.sh` can then be used with the `--no-auth` flag.

Or

Docker login will be performed when running the containers with the `--username [user]` and `--pat [token]` flags

### Starting the containers

If the docker container registry has already been authenticated, start the container with 

```
./deploy.sh -r [service] --no-auth
```

Otherwise, if authentication still needs to be performed, start with

```
./deploy.sh -r [service] --username [username] --pat [token]
```

### Stopping the containers

When the containers need to be stopped, run

```
./deploy.sh -s [service]
```

## Deploy script details
The `deploy.sh` script will automatically configure the XNav deployment in a new (or existing / manually configured) user's home directory in `home/.rebellion`

Before running this script make sure to use `su [account name]` to switch your active user account to the least-priviledged account

If a new user needs to be set up, run `sudo ./deploy.sh --add-user`

Make sure to prepare your .env file using the base `.env.template`

### Script Execution Steps

1. **Check Docker installation:** The script first verifies that Docker is correctly installed and accessible for the current user. If Docker is missing or not functional, you will be prompted to run `deploy.sh --install-prerequisites` to set up Docker and its dependencies.
2. **Add deploy user (optional):** If you want to create a least-privileged user for running and managing the deployment, use:  
   ```
   sudo ./deploy.sh --add-user
   ```
   Follow the prompts to create the user and securely set the password.
3. **Switch to deploy user:** Use `su [account name]` to switch to the new or designated user account.
4. **Prepare environment variables:** Ensure your `.env` file is set up in the deployment directory as needed for your environment.
5. **Fetch or update deployment files: (Automatic on initial run)**  
   To install or update the repository files in your home directory (`~/.rebellion`), run:  
   ```
   ./deploy.sh --update
   ```
   The script will clone the repository if it doesn't exist, or pull the latest changes and back up any existing configurations.
6. **Authenticate with GitHub Container Registry (optional/first run):**  
   When running services that pull from private GitHub Container Registry images, authenticate using:  
   ```
   ./deploy.sh --username [your-github-username] --pat [your-personal-access-token] --run [service]
   ```
   (Replace `[service]` with the service you wish to start, e.g., `postgres`, `api`, `frontend` or `comms`.)
   - To skip authentication (for local images), use `--no-auth`.
7. **Start/Stop Services:**  
   - To start a service:  
     ```
     ./deploy.sh --run [service]
     ```
   - To stop a service:  
     ```
     ./deploy.sh --stop [service]
     ```
8. **Maintenance:**  
   To update the deployment or refresh the repository, rerun step 5 as needed.

