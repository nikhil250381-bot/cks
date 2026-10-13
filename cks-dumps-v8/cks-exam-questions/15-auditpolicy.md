# 🧩 Problem Statement(Kubernetes API Log Auditing)

<details>
<summary>Click to expand the problem statement</summary>

A kubeadm-based Kubernetes cluster does **not** have API auditing enabled.

You must:

1. Enable auditing on the API server using an existing baseline audit policy file.
2. Ensure audit logs are written to disk with proper rotation and retention settings.
3. Extend the baseline audit policy to capture additional specific API requests.

---

### 📋 Given Information

* Basic audit policy is located at:
```
  /etc/kubernetes/logpolicy/sample-policy.yaml
```

* Store audit logs at:
```
  /var/log/kubernetes/audit-logs.txt
```

* Retain a maximum of **2 log files** for up to **10 days**

> 📌 Note: The basic policy only specifies what **not** to log.

---

### 🎯 Required Audit Behavior

Your extended policy must ensure:

* The **`namespace`** resource is logged at **RequestResponse** level

* **ConfigMap** requests in the **`frontend`** namespace must log **request bodies**

* Updates/changes to **ConfigMaps** and **Secrets** in **all namespaces** must be logged at **Metadata** level

* Everything else should default to **Metadata** level

Finally, confirm the API server is using your updated audit policy.

</details>

---

# 🛠 Setup Practice Scenario

<details>
<summary>Click to expand setup steps</summary>


| Script | Purpose |
|--------|---------|
| `setup_q15_problem_scenario.sh` | Creates dirs, baseline policy, mounts volumes in kube-apiserver — run before practice (re-run anytime) |

---

### 📥 Script: setup_q15_problem_scenario.sh
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q15: Kubernetes API Log Auditing
# Creates audit dirs, baseline policy, patches kube-apiserver
# Run on: controlplane node
# ============================================================

set -euo pipefail

POLICY_DIR="/etc/kubernetes/logpolicy"
LOG_DIR="/var/log/kubernetes"
POLICY_FILE="$POLICY_DIR/sample-policy.yaml"
APISERVER_MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"

echo ""
echo "==========================================="
echo " CKS Q15 — Setting up API Audit scenario..."
echo "==========================================="
echo ""

# ── Step 1: Clean previous Q15 state ─────────────────────────
echo "[1/4] Cleaning up any previous Q15 state..."

sudo python3 - <<'PYEOF'
import yaml

manifest_path = "/etc/kubernetes/manifests/kube-apiserver.yaml"

with open(manifest_path, "r") as f:
    manifest = yaml.safe_load(f)

spec = manifest["spec"]
container = spec["containers"][0]

# Remove audit flags
audit_flags = [
    "--audit-policy-file",
    "--audit-log-path",
    "--audit-log-maxage",
    "--audit-log-maxbackup",
    "--audit-log-maxsize"
]
args = container.get("command", [])
args = [a for a in args if not any(a.startswith(f) for f in audit_flags)]
container["command"] = args

# Remove audit volumeMounts
mounts = container.get("volumeMounts", [])
container["volumeMounts"] = [
    m for m in mounts
    if m.get("name") not in ("audit-policy", "audit-logs")
]

# Remove audit volumes
volumes = spec.get("volumes", [])
spec["volumes"] = [
    v for v in volumes
    if v.get("name") not in ("audit-policy", "audit-logs")
]

with open(manifest_path, "w") as f:
    yaml.dump(manifest, f, default_flow_style=False)

print("  Audit flags + volumes cleaned from kube-apiserver.")
PYEOF

# Reset policy file to baseline (in case user extended it)
sudo rm -f "$POLICY_FILE"
sudo truncate -s 0 "$LOG_DIR/audit-logs.txt" 2>/dev/null || true

echo "  Audit log cleared."
echo "  Previous state cleaned."

# ── Step 2: Create directories ────────────────────────────────
echo "[2/4] Creating audit directories..."

sudo mkdir -p "$POLICY_DIR"
sudo mkdir -p "$LOG_DIR"
sudo touch "$LOG_DIR/audit-logs.txt"
echo "  $POLICY_DIR created."
echo "  $LOG_DIR/audit-logs.txt created."

# ── Step 3: Create baseline audit policy ─────────────────────
echo "[3/4] Creating baseline audit policy..."

sudo tee "$POLICY_FILE" > /dev/null <<'EOF'
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: None
    resources:
    - group: ""
      resources: ["configmaps"]
      resourceNames: ["controller-leader"]

  - level: None
    users: ["system:kube-proxy"]
    verbs: ["watch"]
    resources:
    - group: ""
      resources: ["endpoints", "services"]
EOF

echo "  Baseline policy created at $POLICY_FILE"

# ── Step 4: Mount volumes in kube-apiserver ───────────────────
echo "[4/4] Patching kube-apiserver with audit volumes..."

sudo python3 - <<'PYEOF'
import yaml

manifest_path = "/etc/kubernetes/manifests/kube-apiserver.yaml"

with open(manifest_path, "r") as f:
    manifest = yaml.safe_load(f)

spec = manifest["spec"]
container = spec["containers"][0]

# Add audit-policy volumeMount
mounts = container.get("volumeMounts", [])
if not any(m.get("name") == "audit-policy" for m in mounts):
    mounts.append({
        "name": "audit-policy",
        "mountPath": "/etc/kubernetes/logpolicy",
        "readOnly": True
    })
if not any(m.get("name") == "audit-logs" for m in mounts):
    mounts.append({
        "name": "audit-logs",
        "mountPath": "/var/log/kubernetes"
    })
container["volumeMounts"] = mounts

# Add audit volumes
volumes = spec.get("volumes", [])
if not any(v.get("name") == "audit-policy" for v in volumes):
    volumes.append({
        "name": "audit-policy",
        "hostPath": {
            "path": "/etc/kubernetes/logpolicy",
            "type": "DirectoryOrCreate"
        }
    })
if not any(v.get("name") == "audit-logs" for v in volumes):
    volumes.append({
        "name": "audit-logs",
        "hostPath": {
            "path": "/var/log/kubernetes",
            "type": "DirectoryOrCreate"
        }
    })
spec["volumes"] = volumes

with open(manifest_path, "w") as f:
    yaml.dump(manifest, f, default_flow_style=False)

print("  audit-policy + audit-logs volumes added to kube-apiserver.")
PYEOF

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
echo "✅ Q15 scenario is ready!"
echo ""
echo "   Start the Solution!:"
echo ""
```

</details>

---

# ✅ Solution

<details>
<summary>Click to expand the solution</summary>

---

### Step 1: Extend the audit policy

Edit the baseline policy file:

```bash
sudo vim /etc/kubernetes/logpolicy/sample-policy.yaml
```

Append the following rules **after existing rules**, ensuring proper order:

```yaml
  # 1) Log namespaces at RequestResponse level
  - level: RequestResponse
    resources:
    - group: ""
      resources: ["namespaces"]

  # 2) Log request bodies for ConfigMaps in frontend namespace
  - level: Request
    namespaces: ["frontend"]
    resources:
    - group: ""
      resources: ["configmaps"]

  # 3) Log ConfigMaps and Secrets in all namespaces at Metadata level
  - level: Metadata
    verbs: ["create", "update", "patch", "delete"]
    resources:
    - group: ""
      resources: ["configmaps", "secrets"]

  # 4) Default rule for everything else
  - level: Metadata
    omitStages:
    - "RequestReceived"
```

⚠️ Important:
Audit rules are evaluated **top-down**.
More specific rules must appear **before** broader/default rules.

---

### Step 2: Enable auditing on kube-apiserver (static pod)

Edit the API server manifest:

```bash
sudo vim /etc/kubernetes/manifests/kube-apiserver.yaml
```

Ensure the following flags are present under `command:`:

```yaml
- --audit-policy-file=/etc/kubernetes/logpolicy/sample-policy.yaml
- --audit-log-path=/var/log/kubernetes/audit-logs.txt
- --audit-log-maxage=10
- --audit-log-maxbackup=2
- --audit-log-maxsize=100
```

Explanation:

* `audit-policy-file` → Path to policy
* `audit-log-path` → File location
* `maxage` → Days to retain logs
* `maxbackup` → Number of rotated files
* `maxsize` → Max size (MB) before rotation

Since kube-apiserver runs as a **static pod**, kubelet will automatically restart it after saving.

---

### Step 3: Verify audit logs

Check whether logs are being written:

```bash
sudo tail -n 50 /var/log/kubernetes/audit-logs.txt
```

Generate activity for testing:

```bash
kubectl create namespace test-audit
kubectl create configmap cm-test --from-literal=key=value -n frontend
```

Check logs again to confirm entries.

</details>

---


# ↩️ Restore Cluster State


<details>
<summary>Click to expand setup steps</summary>


| Script | Purpose |
|--------|---------|
| `reset_q15_baseline.sh` | Removes audit config, volumes and directories from kube-apiserver |

---

### 🧹 Script: reset_q15_baseline.sh
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q15: Kubernetes API Log Auditing
# Removes audit config, volumes and directories
# Run on: controlplane node
# ============================================================

set -euo pipefail

POLICY_DIR="/etc/kubernetes/logpolicy"
LOG_DIR="/var/log/kubernetes"

echo ""
echo "==========================================="
echo " CKS Q15 — Restoring cluster to baseline..."
echo "==========================================="
echo ""

# ── Step 1: Remove audit config from kube-apiserver ──────────
echo "[1/3] Removing audit config from kube-apiserver..."

sudo python3 - <<'PYEOF'
import yaml

manifest_path = "/etc/kubernetes/manifests/kube-apiserver.yaml"

with open(manifest_path, "r") as f:
    manifest = yaml.safe_load(f)

spec = manifest["spec"]
container = spec["containers"][0]

# Remove audit flags
audit_flags = [
    "--audit-policy-file",
    "--audit-log-path",
    "--audit-log-maxage",
    "--audit-log-maxbackup",
    "--audit-log-maxsize"
]
args = container.get("command", [])
args = [a for a in args if not any(a.startswith(f) for f in audit_flags)]
container["command"] = args

# Remove audit volumeMounts
mounts = container.get("volumeMounts", [])
container["volumeMounts"] = [
    m for m in mounts
    if m.get("name") not in ("audit-policy", "audit-logs")
]

# Remove audit volumes
volumes = spec.get("volumes", [])
spec["volumes"] = [
    v for v in volumes
    if v.get("name") not in ("audit-policy", "audit-logs")
]

with open(manifest_path, "w") as f:
    yaml.dump(manifest, f, default_flow_style=False)

print("  Audit flags + volumes removed from kube-apiserver.")
PYEOF

# ── Step 2: Remove audit directories ─────────────────────────
echo "[2/3] Removing audit directories..."

sudo rm -rf "$POLICY_DIR"
sudo rm -rf "$LOG_DIR"
echo "  $POLICY_DIR removed."
echo "  $LOG_DIR removed."

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
echo "[3/3] Waiting for API server to restart..."

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