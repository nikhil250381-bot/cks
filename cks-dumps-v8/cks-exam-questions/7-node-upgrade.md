# 🧩 Problem Statement(Kubernetes Worker Node Upgrade -kubeadm)

<details>
<summary>Click to expand the problem statement</summary>

In a Kubernetes cluster initialized using **kubeadm**, the control plane has already been upgraded to a newer Kubernetes version.

However, one worker node was intentionally left on an older version to avoid disrupting active workloads.

You are required to:

* SSH into the worker node **`node01`**
* Safely upgrade its Kubernetes components
* Ensure it matches the **current control plane version**
* Perform the upgrade **without impacting running workloads**

---

### 📌 Important Notes

* Use the provided SSH access to connect to `node01`
* Only upgrade Kubernetes components (no application-level changes)
* After completing the upgrade, exit the node properly

</details>

---

# 🛠 Setup Practice Scenario

<details>
<summary>Click to expand setup steps</summary>


| Script | Run on | Purpose |
|--------|--------|---------|
| `setup_q07_controlplane.sh` | controlplane | Upgrade CP to v1.35.2 + generate SSH key |
---


### 📥 Script : setup_q07_controlplane.sh
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q07: Worker Node Upgrade
# setup_q07.sh
# Upgrades CP to v1.35.2 + downgrades node01 to v1.35.1
# Run on: controlplane node
# ============================================================

set -euo pipefail

TARGET_CP_VERSION="1.35.2"
TARGET_NODE_VERSION="1.35.1"

echo ""
echo "==========================================="
echo " CKS Q07 — Setup: Worker Node Upgrade"
echo "==========================================="
echo ""

# ── Step 1: Upgrade control plane ────────────────────────────
echo "[1/2] Checking control plane version..."

CURRENT=$(kubectl get node controlplane \
    -o jsonpath='{.status.nodeInfo.kubeletVersion}' | sed 's/v//')
echo "  Current: v$CURRENT"

if [ "$CURRENT" != "$TARGET_CP_VERSION" ]; then
    echo "  Upgrading control plane to v$TARGET_CP_VERSION..."

    sudo apt-mark unhold kubeadm
    sudo apt-get update -qq
    sudo apt-get install -y kubeadm=${TARGET_CP_VERSION}-*
    sudo apt-mark hold kubeadm

    sudo kubeadm upgrade apply v${TARGET_CP_VERSION} --yes

    sudo apt-mark unhold kubelet kubectl
    sudo apt-get install -y \
        kubelet=${TARGET_CP_VERSION}-* \
        kubectl=${TARGET_CP_VERSION}-*
    sudo apt-mark hold kubelet kubectl
    sudo systemctl daemon-reload
    sudo systemctl restart kubelet
    echo "  Control plane upgraded to v$TARGET_CP_VERSION."
else
    echo "  Already at v$TARGET_CP_VERSION — skipping."
fi

# ── Step 2: Downgrade node01 via SSH ─────────────────────────
echo "[2/2] Downgrading node01 to v$TARGET_NODE_VERSION..."

ssh node01 bash <<ENDSSH
set -euo pipefail
sudo apt-mark unhold kubeadm kubelet kubectl
sudo apt-get update -qq
sudo apt-get install -y --allow-downgrades \
    kubeadm=${TARGET_NODE_VERSION}-* \
    kubelet=${TARGET_NODE_VERSION}-* \
    kubectl=${TARGET_NODE_VERSION}-*
sudo apt-mark hold kubeadm kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet
echo "  node01 downgraded to ${TARGET_NODE_VERSION}."
ENDSSH

echo "  Waiting for kubelet to re-register..."
sleep 20
kubectl get nodes

sleep 5
kubectl get nodes

echo ""
echo "✅ Q07 scenario is ready!"
echo ""
echo "  controlplane : v$TARGET_CP_VERSION  ✔"
echo "  node01       : v$TARGET_NODE_VERSION  ✔"
echo ""
echo "  Now ssh node01 and complete the upgrade. 💪"
echo ""
```

</details>


---

# ✅ Solution

<details>
<summary>Click to expand the solution</summary>

### Step 1: Check current versions

From the control plane node:

```
kubectl get nodes
```

Example output:

```
NAME           STATUS   ROLES           AGE    VERSION
controlplane   Ready    control-plane   102m   v1.35.2
node01         Ready    <none>          64m    v1.33.1
```

Here, `node01` is running an older version.

---

### Step 2: SSH into the worker node

```
ssh node01
```

---

### Step 3: Upgrade kubeadm

Unhold kubeadm:

```
sudo apt-mark unhold kubeadm
```

Update package list:

```
sudo apt update
```

Install the required version (same as control plane):

```
sudo apt install -y kubeadm=1.35.2-*
```

---

### Step 4: Run kubeadm node upgrade

On worker nodes, use:

```
sudo kubeadm upgrade node
```

This updates the node configuration.

---

### Step 5: Upgrade kubelet and kubectl

Unhold packages:

```
sudo apt-mark unhold kubelet kubectl
```

Install the required versions:

```
sudo apt install -y kubelet=1.35.2-* kubectl=1.35.2-*
```

Hold them again (recommended):

```
sudo apt-mark hold kubeadm kubelet kubectl
```

---

### Step 6: Restart kubelet

```
sudo systemctl restart kubelet
```

---

### Step 7: Exit the worker node

```
exit
```

---

### Step 8: Verify upgrade

From control plane:

```
kubectl get nodes
```

Expected output:

```
NAME           STATUS   ROLES           AGE    VERSION
controlplane   Ready    control-plane   105m   v1.35.2
node02         Ready    <none>          67m    v1.33.2
```

The worker node is now successfully upgraded.

</details>

---
