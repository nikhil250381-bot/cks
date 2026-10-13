# 🧩 Problem Statement(Securing the Docker Daemon)

<details>
<summary>Click to expand the problem statement</summary>

A Kubernetes worker node requires immediate hardening due to insecure Docker daemon configuration.

The node currently:

* Allows unnecessary user-level access to the Docker socket
* May be exposing the Docker API over the network

Both issues can lead to serious security risks.

You must log in to node **`cks1011`** and apply the required security fixes without impacting cluster stability.

---

### 🎯 Task

On node, complete the following:

1. Remove user **`developer`** from the `docker` group

   * Do not remove the user from any other groups

2. Update and restart Docker so that:

   * `/var/run/docker.sock` is owned by the **root group**

3. Ensure Docker is **not listening on any TCP port**

   * It should only use the Unix socket

---

### 📌 Notes

* Restart Docker after applying changes
* Confirm the Kubernetes cluster remains healthy

</details>

---

# 🛠 Setup Practice Scenario

<details>
<summary>Click to expand setup steps</summary>


| Script |          Purpose |
|--------|------------------|
| `setup_q16_problem_scenario.sh` | Installs Docker, creates insecure config — run before practice (re-run anytime) |

---

### 📥 Script: setup_q16_problem_scenario.sh
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q16: Securing the Docker Daemon
# Installs Docker + creates insecure config for practice
# ============================================================

set -euo pipefail

echo ""
echo "==========================================="
echo " CKS Q16 — Setting up Docker daemon scenario..."
echo "==========================================="
echo ""

# ── Step 1: Clean previous state ─────────────────────────────
# ── Step 1: Clean previous state ─────────────────────────────
# ── Step 1: Clean previous state ─────────────────────────────
echo "[1/5] Cleaning up any previous Q13 state..."

if ! command -v docker &>/dev/null; then
    echo "  Docker not installed — nothing to clean."
else
    # Re-add developer to docker group if removed during previous practice
    if id developer &>/dev/null; then
        if ! id -nG developer | grep -qw docker; then
            sudo usermod -aG docker developer
            echo "  developer re-added to docker group."
        fi
    fi

    # Restore docker.service TCP flag if removed during previous practice
    if [ -f /usr/lib/systemd/system/docker.service ]; then
        if ! grep -q "tcp://0.0.0.0:2375" /usr/lib/systemd/system/docker.service; then
            sudo sed -i \
                's|ExecStart=/usr/bin/dockerd -H fd://|ExecStart=/usr/bin/dockerd -H fd:// -H tcp://0.0.0.0:2375|' \
                /usr/lib/systemd/system/docker.service
            echo "  TCP 2375 flag restored in docker.service."
        fi
    fi

    # Restore docker.socket SocketGroup if changed during previous practice
    if [ -f /usr/lib/systemd/system/docker.socket ]; then
        sudo sed -i 's/SocketGroup=root/SocketGroup=docker/' \
            /usr/lib/systemd/system/docker.socket
        echo "  docker.socket SocketGroup restored to docker."
    fi

    # Reload after all file changes in cleanup
    sudo systemctl daemon-reload
    sudo systemctl stop docker docker.socket 2>/dev/null || true
    sudo systemctl start docker.socket
    echo "  Previous state cleaned."
fi

# ── Step 2: Install Docker (skip if already installed) ───────
echo "[2/5] Checking Docker installation..."

if command -v docker &>/dev/null; then
    echo "  Docker already installed — skipping."
else
    echo "  Installing Docker..."

    sudo apt-get update -qq
    sudo apt-get install -y -qq ca-certificates curl

    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    sudo apt-get update -qq
    sudo apt-get install -y -qq \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin

    echo "  Docker installed."
fi

# ── Step 3: Create developer user ────────────────────────────
echo "[3/5] Setting up developer user..."

if id developer &>/dev/null; then
    echo "  User developer already exists — skipping."
else
    sudo useradd developer
    echo "  User developer created."
fi

# Add developer to docker group
if ! id -nG developer | grep -qw docker; then
    sudo usermod -aG docker developer
    echo "  developer added to docker group."
else
    echo "  developer already in docker group — skipping."
fi

echo "  Verify: $(id developer)"

# ── Step 4: Enable TCP 2375 in docker.service ────────────────
echo "[4/5] Enabling TCP 2375 in docker.service..."

if grep -q "tcp://0.0.0.0:2375" /usr/lib/systemd/system/docker.service; then
    echo "  TCP 2375 already configured — skipping."
else
    sudo sed -i \
        's|ExecStart=/usr/bin/dockerd -H fd://|ExecStart=/usr/bin/dockerd -H fd:// -H tcp://0.0.0.0:2375|' \
        /usr/lib/systemd/system/docker.service
    echo "  TCP 2375 added to docker.service."
fi

# ── Step 5: Reload + restart Docker ──────────────────────────
# ── Step 5: Reload + restart Docker ──────────────────────────
echo "[5/5] Reloading and restarting Docker..."

sudo systemctl daemon-reload
sudo systemctl stop docker docker.socket 2>/dev/null || true
sudo systemctl start docker.socket
sudo systemctl start docker

echo "  Verifying TCP port 2375..."
sleep 3
if sudo ss -tunlp | grep -q 2375; then
    echo "  ✔ Docker listening on TCP 2375."
else
    echo "  ⚠ TCP 2375 not detected — check docker.service manually."
fi

echo "  Verifying docker.sock group..."
ls -lh /var/run/docker.sock

echo ""
echo "✅ Q16 scenario is ready!"
echo ""
echo "Start the Solution!"
echo ""
```

</details>

---

# ✅ Solution

<details>
<summary>Click to expand the solution</summary>

---

### Step 1: Check if `developer` belongs to the docker group

```
id developer
```

Example output:

```
uid=1001(developer) gid=1001(developer) groups=1001(developer),988(docker)
```

---

### Step 2: Remove `developer` from docker group

```
sudo gpasswd -d developer docker
```

Verify:

```
id developer
```

Now it should no longer show `docker` in the group list.

---

### Step 3: Fix Docker socket group ownership

Check current socket permissions:

```
ls -lh /var/run/docker.sock
```

If the group is `docker`, update it.

Edit the systemd socket file:

```
sudo vim /usr/lib/systemd/system/docker.socket
```

Change:

**From**

```
SocketGroup=docker
```

**To**

```
SocketGroup=root
```

Save and reload systemd:

```
sudo systemctl daemon-reload
sudo systemctl restart docker.socket
```

Verify again:

```
ls -lh /var/run/docker.sock
```

Expected:

```
srw-rw---- 1 root root ...
```

---

### Step 4: Ensure Docker is not listening on TCP port 2375

Check listening ports:

```
sudo netstat -tunlp | grep 2375
```

If you see:

```
tcp6  0  0 :::2375  :::*  LISTEN
```

Docker is exposed over TCP.

---

### Step 5: Remove TCP listener from Docker service

Edit the service file:

```
sudo vim /usr/lib/systemd/system/docker.service
```

Remove this option from `ExecStart`:

```
-H tcp://0.0.0.0:2375
```

It should look similar to:

```
ExecStart=/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock
```

Reload and restart Docker:

```
sudo systemctl daemon-reload
sudo systemctl restart docker
```

---

### Step 6: Verify TCP port is closed

```
sudo netstat -tunlp | grep 2375
```

No output should appear.

---

### Step 7: Verify cluster health

From control plane:

```
kubectl get nodes
kubectl get pods -A
```

All nodes and Pods should remain in `Ready` and `Running` state.

</details>

---

# ↩️ Restore Cluster State


<details>
<summary>Click to expand setup steps</summary>


| Script |          Purpose |
|--------|------------------|
| `reset_q16_baseline.sh`   |  Removes Docker completely — run before moving to next problem |

---

### 🧹 Script: reset_q16_baseline.sh
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q16: Securing the Docker Daemon
# Removes Docker completely — restores node01 to baseline
# ============================================================

set -euo pipefail

echo ""
echo "==========================================="
echo " CKS Q16 — Restoring node01 to baseline..."
echo "==========================================="
echo ""

# ── Step 1: Stop Docker ───────────────────────────────────────
echo "[1/3] Stopping Docker..."

sudo systemctl stop docker docker.socket 2>/dev/null || true
sudo systemctl disable docker 2>/dev/null || true
echo "  Docker stopped and disabled."

# ── Step 2: Remove Docker packages ───────────────────────────
echo "[2/3] Removing Docker..."

sudo apt-get purge -y -qq \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
sudo apt-get autoremove -y -qq 2>/dev/null || true

# Remove Docker repo + keyring
sudo rm -f /etc/apt/sources.list.d/docker.sources
sudo rm -f /etc/apt/keyrings/docker.asc
sudo apt-get update -qq

echo "  Docker removed."

# ── Step 3: Remove developer user ────────────────────────────
echo "[3/3] Removing developer user..."

if id developer &>/dev/null; then
    sudo userdel developer 2>/dev/null || true
    echo "  developer user removed."
else
    echo "  developer user not found — skipping."
fi

echo ""
echo "✅ Cluster is back to baseline!"
echo ""
echo "   Safe to move to next problem. 🚀"
echo ""
```

</details>

---