# 🧩 Problem Statement(Hardening Kubelet and ETCD Configuration)

<details>
<summary>Click to expand the problem statement</summary>

A Kubernetes cluster created using **kubeadm** was scanned using a **CIS Benchmark tool**, and multiple critical security violations were reported.

Your task is to:

1. Log in to the **appropriate node**
2. Identify and fix the reported security issues
3. Restart the affected components so the new configuration takes effect

### 🔐 Fix the following violations related to kubelet:

* Ensure `anonymous-auth` is set to `false`
* Ensure `--authorization-mode` is **not** set to `AlwaysAllow`
  
`Note`: Wherever possible, use **Webhook-based authentication and authorization**

### 🔐 Fix the following violation related to etcd:

* Ensure the `--client-cert-auth` parameter is set to `true`

</details>

---

# 🛠 Setup Practice Scenario

<details>
<summary>Click to expand setup steps</summary>


| Script | Purpose |
|--------|---------|
| `setup_q01_problem_scenario.sh` | Introduces insecure config — run before practice |

---

### 📥 Script : setup_q01_problem_scenario.sh

Run this **before you start practicing** this problem.
It introduces insecure kubelet and etcd configurations.
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q01: Hardening Kubelet and ETCD
# setup_problem_scenario.sh
# Introduces insecure configuration for practice
# Run on: controlplane node
# ============================================================

set -euo pipefail

KUBELET_CONFIG="/var/lib/kubelet/config.yaml"
ETCD_MANIFEST="/etc/kubernetes/manifests/etcd.yaml"

echo ""
echo "==========================================="
echo " CKS Q01 — Setting up insecure scenario..."
echo "==========================================="
echo ""

# ── Patch kubelet config ──────────────────────────────────────
echo "[1/3] Patching kubelet config..."

sudo python3 - <<'EOF'
import yaml

config_path = "/var/lib/kubelet/config.yaml"

with open(config_path, "r") as f:
    config = yaml.safe_load(f)

config["authentication"]["anonymous"]["enabled"] = True
config["authentication"]["webhook"]["enabled"] = False
config["authorization"]["mode"] = "AlwaysAllow"

with open(config_path, "w") as f:
    yaml.dump(config, f, default_flow_style=False)

print("  kubelet config patched.")
EOF

# ── Patch etcd manifest ───────────────────────────────────────
echo "[2/3] Patching etcd manifest..."

sudo sed -i 's/--client-cert-auth=true/--client-cert-auth=false/' "$ETCD_MANIFEST"
echo "  etcd manifest patched."

# ── Restart kubelet ───────────────────────────────────────────
echo "[3/3] Restarting kubelet..."

sudo systemctl daemon-reload
sudo systemctl restart kubelet
echo "  kubelet restarted."

# ── Force restart kube-apiserver via crictl ───────────────────
echo "  Force restarting kube-apiserver..."

APISERVER_ID=$(sudo crictl ps | grep kube-apiserver | awk '{print $1}')
if [ -n "$APISERVER_ID" ]; then
    sudo crictl stop "$APISERVER_ID"
    echo "  kube-apiserver container stopped — kubelet will recreate it."
else
    echo "  kube-apiserver container not found — may already be restarting."
fi

# ── Wait for API server to come back up ───────────────────────
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
echo "✅ Problem scenario is ready!"
echo "   Now go fix them! 💪"
echo ""
```


## 🔍 Install kube-bench (Optional)


**kube-bench** is an open-source tool that checks whether Kubernetes components comply with the CIS Kubernetes Benchmark.

It reports PASS/FAIL results and provides remediation guidance.

---

### Download kube-bench

```
KUBE_BENCH_VERSION=0.14.0
```

```
curl -L https://github.com/aquasecurity/kube-bench/releases/download/v${KUBE_BENCH_VERSION}/kube-bench_${KUBE_BENCH_VERSION}_linux_amd64.tar.gz -o kube-bench_${KUBE_BENCH_VERSION}_linux_amd64.tar.gz
```

```
tar -xvf kube-bench_${KUBE_BENCH_VERSION}_linux_amd64.tar.gz
```

---

### Run kube-bench

**Scan kubelet:**

```
sudo ./kube-bench run --targets node --config-dir ./cfg/
```

**Scan etcd:**

```
sudo ./kube-bench run --targets etcd --config-dir ./cfg/
```

The tool will show **FAIL** checks along with remediation guidance.
Follow the recommended remediation steps to fix the issues.

</details>

---

# ✅ Solution

<details>
<summary>Click to expand the solution</summary>


### Step 1: Locate the kubelet configuration file

By default, it is located at:

```
/var/lib/kubelet/config.yaml
```

If unsure, verify using:

```
ps -ef | grep kubelet
```

Look for the `--config` argument to confirm the file path.

---

### Step 2: Update kubelet configuration

Open the file:

```
sudo vim /var/lib/kubelet/config.yaml
```

Modify the configuration as shown below:

```yaml
authentication:
  anonymous:
    enabled: false   # Change from true to false
  webhook:
    enabled: true    # Change from false to true
    cacheTTL: 0s
  x509:
    clientCAFile: /etc/kubernetes/pki/ca.crt

authorization:
  mode: Webhook      # Change from AlwaysAllow to Webhook
  webhook:
    cacheAuthorizedTTL: 0s
    cacheUnauthorizedTTL: 0s
```

Save and exit.

---

### Step 3: Update ETCD configuration

Open the etcd static pod manifest:

```
sudo vim /etc/kubernetes/manifests/etcd.yaml
```

Ensure the following flag is set:

```yaml
- --client-cert-auth=true   # Change from false to true
```

Save and exit.

---

### Step 4: Restart kubelet

```
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

---

### Step 5: Verify cluster status

```
kubectl get nodes
```

If the node shows `Ready` status and the API server is reachable, the configuration has been applied successfully.

</details>

---


# ↩️ Restore Cluster State

<details>
<summary>Click to expand setup steps</summary>

| Script | Purpose |
|--------|---------|
| `reset_q01_baseline.sh` | Moving to next problem? Run this to restore clean cluster state |


---

### 🧹 Script : reset_q01_baseline.sh

**Done with this problem? Moving to the next one?**
Run this to restore the cluster back to a clean kubeadm baseline state,
so this problem's changes don't interfere with the next scenario.
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q01: Hardening Kubelet and ETCD
# reset_to_baseline.sh
# Restores cluster to clean kubeadm baseline (secure defaults)
# Run on: controlplane node
# ============================================================

set -euo pipefail

KUBELET_CONFIG="/var/lib/kubelet/config.yaml"
ETCD_MANIFEST="/etc/kubernetes/manifests/etcd.yaml"

echo ""
echo "==========================================="
echo " CKS Q01 — Restoring cluster to baseline..."
echo "==========================================="
echo ""

# ── Restore kubelet config ────────────────────────────────────
echo "[1/3] Restoring kubelet config to secure defaults..."

sudo python3 - <<'EOF'
import yaml

config_path = "/var/lib/kubelet/config.yaml"

with open(config_path, "r") as f:
    config = yaml.safe_load(f)

config["authentication"]["anonymous"]["enabled"] = False
config["authentication"]["webhook"]["enabled"] = True
config["authorization"]["mode"] = "Webhook"

with open(config_path, "w") as f:
    yaml.dump(config, f, default_flow_style=False)

print("  kubelet config restored.")
EOF

# ── Restore etcd manifest ─────────────────────────────────────
echo "[2/3] Restoring etcd manifest..."

# Handle both directions (whether currently true or false)
sudo sed -i 's/--client-cert-auth=false/--client-cert-auth=true/' "$ETCD_MANIFEST"
echo "  etcd manifest restored."

# ── Restart kubelet ───────────────────────────────────────────
echo "[3/3] Restarting kubelet..."

sudo systemctl daemon-reload
sudo systemctl restart kubelet
echo "  kubelet restarted."

# ── Force restart kube-apiserver via crictl ───────────────────
echo "  Force restarting kube-apiserver..."

APISERVER_ID=$(sudo crictl ps | grep kube-apiserver | awk '{print $1}')
if [ -n "$APISERVER_ID" ]; then
    sudo crictl stop "$APISERVER_ID"
    echo "  kube-apiserver container stopped — kubelet will recreate it."
else
    echo "  kube-apiserver container not found — may already be restarting."
fi

# ── Wait for API server to come back up ───────────────────────
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