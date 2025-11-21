# Deployment Instructions


## Deploy script
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

