# Deployment Instructions

## Deployment with Komodo

The Komodo deployment uses a shared directory at `/opt/rebellion/deploy`, owned by a dedicated service user.

Ensure `curl` is installed (`sudo apt-get install curl`) before bootstrapping.

### Prerequisite setup (elevated)

Initial setup **must be run elevated with sudo** as root. One command installs prerequisites, creates the service user, and prompts to clone the repository into `/opt/rebellion/deploy`:

```bash
sudo bash -c 'source <(curl -s https://raw.githubusercontent.com/Rebellion-Automation/deploy/refs/heads/main/deploy-komodo-v2.sh)'
```

Press **Enter** (or **y**) at each prompt to accept defaults — prerequisites, service user, and repo clone happen in one session.

If you skipped initialization, switch to the service user and run the script again (no sudo):

```bash
su [username]
source <(curl -s https://raw.githubusercontent.com/Rebellion-Automation/deploy/refs/heads/main/deploy-komodo-v2.sh)
```

You can still run individual steps explicitly:

```bash
# Prerequisites only (also prompts to create service user afterward)
sudo bash -c 'source <(curl -s https://raw.githubusercontent.com/Rebellion-Automation/deploy/refs/heads/main/deploy-komodo-v2.sh) -p'

# Service user only
sudo bash -c 'source <(curl -s https://raw.githubusercontent.com/Rebellion-Automation/deploy/refs/heads/main/deploy-komodo-v2.sh) -a'
```

### Initialize deployment (service user)

If initialization was skipped during setup, switch to the service user — **do not use sudo**:

```bash
su [username]

source <(curl -s https://raw.githubusercontent.com/Rebellion-Automation/deploy/refs/heads/main/deploy-komodo-v2.sh)
```

When sourced, your shell will `cd` into `/opt/rebellion/deploy`. Initialization generates a WireGuard keypair at `/opt/rebellion/wireguard/` for connecting to the telemetry ingester. Register the displayed **public key** with your telemetry administrator.

After initialization, run all further commands from the shared directory:

```bash
cd /opt/rebellion/deploy && ./deploy.sh --help
```
