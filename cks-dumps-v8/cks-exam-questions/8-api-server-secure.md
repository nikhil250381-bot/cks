# 🧩 Problem Statement(Securing API Server Authentication & Authorization)

<details>
<summary>Click to expand the problem statement</summary>

A Kubernetes cluster built using **kubeadm** was temporarily left in an insecure state for testing purposes.

The API server is currently configured to allow requests without proper authentication and authorization. This presents a serious security risk.

Your task is to restore secure access controls by hardening the API server configuration and removing any anonymous permissions.


### 🎯 Task

Update the Kubernetes API server configuration to enforce the following security settings:

1. Disable **anonymous authentication**
2. Configure authorization to use only:

   * `Node`
   * `RBAC`
3. Enable the admission controller:

   * `NodeRestriction`

After securing the API server, remove unnecessary anonymous access by deleting the following ClusterRoleBinding:

```
system:anonymous
```

</details>

---

# 🛠 Setup Practice Scenario

<details>
<summary>Click to expand setup steps</summary>


| Script | Purpose |
|--------|---------|
| `setup_q08_problem_scenario.sh` | Adds anonymous-auth, creates anonymous kubeconfig + CRB — run before practice (re-run anytime) |

---

### 📥 Script: setup_q08_problem_scenario.sh
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q08: Securing API Server Auth & Authz
# setup_problem_scenario.sh
# Run on: controlplane node
# ============================================================

set -euo pipefail


echo ""
echo "==========================================="
echo " CKS Q08 — Setting up insecure API server..."
echo "==========================================="
echo ""

# ── Step 1: Patch kube-apiserver — add anonymous-auth=true ───
echo "[1/5] Patching kube-apiserver..."

# ── Step 1: Clean --anonymous-auth if left from previous practice ──
echo "[1/5] Cleaning kube-apiserver (removing --anonymous-auth if present)..."

sudo python3 - <<'PYEOF'
import yaml

manifest_path = "/etc/kubernetes/manifests/kube-apiserver.yaml"

with open(manifest_path, "r") as f:
    manifest = yaml.safe_load(f)

container = manifest["spec"]["containers"][0]
args = container.get("command", [])

if any(a.startswith("--anonymous-auth=") for a in args):
    args = [a for a in args if not a.startswith("--anonymous-auth=")]
    container["command"] = args
    with open(manifest_path, "w") as f:
        yaml.dump(manifest, f, default_flow_style=False)
    print("  --anonymous-auth removed (left from previous practice).")
else:
    print("  --anonymous-auth not present — nothing to clean.")

print("  --authorization-mode       → unchanged (Node,RBAC)")
print("  --enable-admission-plugins → unchanged (NodeRestriction)")
PYEOF

# ── Step 2: Backup admin.conf ─────────────────────────────────
echo "[2/5] Backing up admin.conf to ~/.kube/admin.conf..."

mkdir -p "$HOME/.kube"
sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/admin.conf"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/admin.conf"
echo "  admin.conf backed up."


# ── Force restart kube-apiserver via crictl ───────────────────
echo "  Force restarting kube-apiserver..."

APISERVER_ID=$(sudo crictl ps | grep kube-apiserver | awk '{print $1}')
if [ -n "$APISERVER_ID" ]; then
    sudo crictl stop "$APISERVER_ID"
    echo "  kube-apiserver container stopped — kubelet will recreate it."
else
    echo "  kube-apiserver container not found — may already be restarting."
fi

# ── Step 3: Wait for API server to restart ───────────────────
echo "[3/5] Waiting for API server to restart..."

sleep 10
for i in $(seq 1 30); do
    if kubectl --kubeconfig="$HOME/.kube/admin.conf" get nodes &>/dev/null; then
        echo "  API server is back up."
        break
    fi
    echo "  Waiting... ($i/30)"
    sleep 3
done

# ── Step 4: Create system:anonymous ClusterRoleBinding ────────
echo "[4/5] Creating system:anonymous ClusterRoleBinding..."

kubectl --kubeconfig="$HOME/.kube/admin.conf" \
    delete clusterrolebinding system:anonymous --ignore-not-found

kubectl --kubeconfig="$HOME/.kube/admin.conf" \
    create clusterrolebinding system:anonymous \
    --clusterrole=cluster-admin \
    --user=system:anonymous
echo "  ClusterRoleBinding system:anonymous → cluster-admin created."

# ── Step 5: Replace ~/.kube/config with anonymous kubeconfig ──
echo "[5/5] Creating anonymous kubeconfig..."

APISERVER_IP=$(grep server "$HOME/.kube/admin.conf" \
    | awk -F'https://' '{print $2}' | awk -F':' '{print $1}')

# Remove current config
rm -f "$HOME/.kube/config"

kubectl config set-cluster kubernetes \
    --server="https://${APISERVER_IP}:6443" \
    --insecure-skip-tls-verify=true \
    --kubeconfig="$HOME/.kube/config"

kubectl config set-credentials anon \
    --username=system:anonymous \
    --password=anything \
    --kubeconfig="$HOME/.kube/config"

kubectl config set-context anonymous-context \
    --cluster=kubernetes \
    --user=anon \
    --kubeconfig="$HOME/.kube/config"

kubectl config use-context anonymous-context \
    --kubeconfig="$HOME/.kube/config"

echo "  ~/.kube/config replaced with anonymous kubeconfig."

echo ""
echo "✅ Q08 scenario is ready!"
echo ""
echo "Start the solution!"
echo ""
```

</details>

---

# ✅ Solution

<details>
<summary>Click to expand the solution</summary>

### Step 1: Edit the kube-apiserver manifest

On the control plane node, open:

```
sudo vim /etc/kubernetes/manifests/kube-apiserver.yaml
```

Add or update the following flags under the `command:` section:

```
- --anonymous-auth=false
- --authorization-mode=Node,RBAC
- --enable-admission-plugins=NodeRestriction
```

⚠️ Important:

* If `--authorization-mode` already exists, modify it instead of duplicating.
* If `--enable-admission-plugins` already exists, append `NodeRestriction` to the existing list.
* Avoid overwriting other required admission plugins.

Save and exit.

Since this is a static Pod, the kubelet will automatically restart the API server.

---

### Step 2: Verify API server is running

If anonymous authentication is disabled, unauthenticated `kubectl` calls may fail.

You can verify the API server using:

```
sudo crictl ps | grep kube-apiserver
```

Or use the admin kubeconfig:

```
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes
```

If nodes are listed successfully, the API server is healthy.

---

### Step 3: Remove anonymous ClusterRoleBinding

List ClusterRoleBindings:

```
kubectl --kubeconfig=/etc/kubernetes/admin.conf get clusterrolebinding | grep anonymous
```

You should see:

```
system:anonymous
```

Delete it:

```
kubectl --kubeconfig=/etc/kubernetes/admin.conf delete clusterrolebinding system:anonymous
```

---

### Step 4: Confirm removal

```
kubectl --kubeconfig=/etc/kubernetes/admin.conf get clusterrolebinding | grep anonymous
```

There should be no output.

---

### Step 5: Final verification

Confirm cluster health:

```
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -A
```

All nodes and Pods should remain in `Ready` and `Running` state.

</details>

---

# ↩️ Restore Cluster State


<details>
<summary>Click to expand setup steps</summary>


| Script | Purpose |
|--------|---------|
| `reset_q08_baseline.sh` | Removes anonymous-auth flag, CRB, restores ~/.kube/config |

> ⚠️ Run as **ubuntu user, NOT root**

---

### 🧹 Script: reset_q08_baseline.sh
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q08: Securing API Server Auth & Authz
# reset_to_baseline.sh
# Run on: controlplane node
# ============================================================

set -euo pipefail


echo ""
echo "==========================================="
echo " CKS Q08 — Restoring cluster to baseline..."
echo "==========================================="
echo ""

# ── Step 1: Delete system:anonymous CRB ──────────────────────
echo "[1/3] Removing system:anonymous ClusterRoleBinding..."

kubectl --kubeconfig="$HOME/.kube/admin.conf" \
    delete clusterrolebinding system:anonymous --ignore-not-found
echo "  ClusterRoleBinding removed."

# ── Step 2: Remove --anonymous-auth from kube-apiserver ──────
echo "[2/3] Restoring kube-apiserver to baseline..."

sudo python3 - <<'PYEOF'
import yaml

manifest_path = "/etc/kubernetes/manifests/kube-apiserver.yaml"

with open(manifest_path, "r") as f:
    manifest = yaml.safe_load(f)

container = manifest["spec"]["containers"][0]
args = container.get("command", [])

# Only remove --anonymous-auth — leave all other flags untouched
args = [a for a in args if not a.startswith("--anonymous-auth=")]

container["command"] = args

with open(manifest_path, "w") as f:
    yaml.dump(manifest, f, default_flow_style=False)

print("  --anonymous-auth           → removed (kubeadm baseline: not set)")
print("  --authorization-mode       → unchanged (Node,RBAC)")
print("  --enable-admission-plugins → unchanged (NodeRestriction)")
PYEOF

# ── Step 3: Restore ~/.kube/config ───────────────────────────
echo "[3/3] Restoring ~/.kube/config..."

if [ -f "$HOME/.kube/admin.conf" ]; then
    cp "$HOME/.kube/admin.conf" "$HOME/.kube/config"
    echo "  $HOME/.kube/config restored from $HOME/.kube/admin.conf"
else
    echo "  ⚠ admin.conf backup not found — copying from /etc/kubernetes/admin.conf"
    sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
    sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
fi

# ── Force restart kube-apiserver via crictl ───────────────────
echo "  Force restarting kube-apiserver..."

APISERVER_ID=$(sudo crictl ps | grep kube-apiserver | awk '{print $1}')
if [ -n "$APISERVER_ID" ]; then
    sudo crictl stop "$APISERVER_ID"
    echo "  kube-apiserver container stopped — kubelet will recreate it."
else
    echo "  kube-apiserver container not found — may already be restarting."
fi

echo "  Waiting for API server to restart..."
sleep 10
for i in $(seq 1 30); do
    if kubectl get nodes &>/dev/null; then
        echo "  API server is back up."
        break
    fi
    echo "  Waiting... ($i/30)"
    sleep 3
done

echo ""
echo "✅ Cluster is back to baseline!"
echo ""
echo "   Safe to move to next problem. 🚀"
echo ""
```

</details>

---