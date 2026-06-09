# Deployment Instructions

## Deployment with Komodo

The Komodo deployment uses a shared directory at `/opt/rebellion/deploy`, owned by a dedicated service user.

Ensure `curl` is installed (`sudo apt-get install curl`) before bootstrapping.

### Prerequisite setup (elevated)

Initial setup **must be run elevated with sudo** as root. One command installs prerequisites, creates the service user, and prompts to clone the repository into `/opt/rebellion/deploy`:

```bash
curl -s https://raw.githubusercontent.com/Rebellion-Automation/deploy/refs/heads/main/deploy-komodo-v2.sh | sudo tee /tmp/setup.sh > /dev/null
sudo bash /tmp/setup.sh
```

Press **Enter** (or **y**) at each prompt to accept defaults — prerequisites, service user, and repo clone happen in one session.

If you skipped initialization, switch to the service user and run the script again (no sudo):

```bash
su [username]
curl -s https://raw.githubusercontent.com/Rebellion-Automation/deploy/refs/heads/main/deploy-komodo-v2.sh | tee /tmp/setup.sh > /dev/null
bash /tmp/setup.sh
```

You can still run individual steps explicitly:

```bash
# Prerequisites only (also prompts to create service user afterward)
curl -s https://raw.githubusercontent.com/Rebellion-Automation/deploy/refs/heads/main/deploy-komodo-v2.sh | sudo tee /tmp/setup.sh > /dev/null
sudo bash /tmp/setup.sh -p

# Service user only
curl -s https://raw.githubusercontent.com/Rebellion-Automation/deploy/refs/heads/main/deploy-komodo-v2.sh | sudo tee /tmp/setup.sh > /dev/null
sudo bash /tmp/setup.sh -a
```

### Initialize deployment (service user)

If initialization was skipped during setup, switch to the service user — **do not use sudo**:

```bash
su [username]

curl -s https://raw.githubusercontent.com/Rebellion-Automation/deploy/refs/heads/main/deploy-komodo-v2.sh | tee /tmp/setup.sh > /dev/null
bash /tmp/setup.sh
```

Initialization clones the repo to `/opt/rebellion/deploy` and generates a WireGuard keypair at `/opt/rebellion/wireguard/` for connecting to the telemetry ingester. Register the displayed **public key** with your telemetry administrator.

After initialization, run all further commands from the shared directory:

```bash
cd /opt/rebellion/deploy && ./deploy.sh --help
```
