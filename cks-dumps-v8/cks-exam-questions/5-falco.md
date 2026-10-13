# 🧩 Problem Statement(Detecting a Pod Accessing `/dev/mem`)

<details>
<summary>Click to expand the problem statement</summary>

A suspicious Pod in the cluster has been flagged for abnormal behavior.

A Pod belonging to the **neuron** application is attempting to access the sensitive host device:

```
/dev/mem
```

This indicates a potential security threat and must be stopped.

---

### 🎯 Task

1. Identify the Pod that is accessing `/dev/mem`.
2. Scale the Deployment of the identified Pod down to **zero replicas**.

</details>

---

# 🛠 Setup Practice Scenario

<details>
<summary>Click to expand setup steps</summary>


| Script | Purpose |
|--------|---------|
| `setup_q05_problem_scenario.sh` | Creates neuron namespace, deploys workloads, installs Falco — run before practice (re-run anytime) |

---

### 📥 Script : setup_q05_problem_scenario.sh
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q05: Detecting a Pod Accessing /dev/mem
# setup_problem_scenario.sh
# Deploys neuron workloads and installs Falco
# Run on: controlplane node
# ============================================================

set -euo pipefail

NAMESPACE="neuron"
FALCO_RULES_LOCAL="/etc/falco/falco_rules.local.yaml"

echo ""
echo "==========================================="
echo " CKS Q05 — Setting up /dev/mem scenario..."
echo "==========================================="
echo ""

# ── Step 1: Reset only deployments + Falco rules ─────────────
echo "[1/4] Cleaning up previous deployments and Falco rules..."

for APP in facebook instagram tinder; do
    kubectl delete deployment "$APP" -n "$NAMESPACE" --ignore-not-found
done

if [ -f "$FALCO_RULES_LOCAL" ]; then
    sudo truncate -s 0 "$FALCO_RULES_LOCAL"
    echo "  Falco local rules cleared."
fi

echo "  Previous state cleaned."

# ── Step 2: Install Falco (skip if already installed) ────────
echo "[2/4] Checking Falco installation..."

if command -v falco &>/dev/null; then
    echo "  Falco already installed — skipping."
else
    echo "  Installing Falco..."

    sudo apt-get update -qq
    sudo apt-get install -y curl gnupg2 apt-transport-https -qq

    curl -fsSL https://falco.org/repo/falcosecurity-packages.asc \
        | sudo gpg --dearmor \
        -o /usr/share/keyrings/falco-archive-keyring.gpg

    echo "deb [signed-by=/usr/share/keyrings/falco-archive-keyring.gpg] \
https://download.falco.org/packages/deb stable main" \
        | sudo tee /etc/apt/sources.list.d/falcosecurity.list > /dev/null

    sudo apt-get update -qq
    sudo apt-get install -y falco

    echo "  Falco installed successfully."
fi

# Stop Falco system service — user runs it manually in foreground
sudo systemctl stop falco 2>/dev/null || true
sudo systemctl disable falco 2>/dev/null || true
echo "  Falco system service stopped (user runs it manually)."

# Ensure local rules file exists and is empty
sudo touch "$FALCO_RULES_LOCAL"
sudo truncate -s 0 "$FALCO_RULES_LOCAL"
echo "  Falco local rules file ready (empty): $FALCO_RULES_LOCAL"

# ── Step 3: Ensure namespace exists + deploy workloads ───────
echo "[3/4] Ensuring namespace and deploying workloads..."

if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo "  Namespace '$NAMESPACE' already exists — skipping recreate."
else
    kubectl create namespace "$NAMESPACE"
    echo "  Namespace '$NAMESPACE' created."
fi

for APP in facebook instagram tinder; do
    case "$APP" in
        facebook)  IMAGE="devopstechtales/cks-exam-questions:falco-eg-v1" ;;
        instagram) IMAGE="devopstechtales/cks-exam-questions:falco-eg-v2" ;;
        tinder)    IMAGE="devopstechtales/cks-exam-questions:falco-eg-v3" ;;
    esac

    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $APP
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $APP
  template:
    metadata:
      labels:
        app: $APP
    spec:
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      nodeSelector:
        node-role.kubernetes.io/control-plane: ""
      containers:
      - name: $APP
        image: $IMAGE
EOF

done

echo "  Waiting for pods to be Running on controlplane..."
kubectl wait --for=condition=available deployment/facebook \
    -n "$NAMESPACE" --timeout=120s
kubectl wait --for=condition=available deployment/instagram \
    -n "$NAMESPACE" --timeout=120s
kubectl wait --for=condition=available deployment/tinder \
    -n "$NAMESPACE" --timeout=120s

# ── Step 4: Verify scenario state ────────────────────────────
echo "[4/4] Verifying scenario state..."
kubectl get pods -n "$NAMESPACE"

echo ""
echo "✅ Q05 scenario is ready!"
echo ""
echo "Start the solution!"
echo ""
```

</details>

---

# ✅ Solution

<details>
<summary>Click to expand the solution</summary>

### Step 1: Check Pods in the `neuron` namespace

```
kubectl get pods -n neuron
```

---

### Step 2: Create a Falco rule to detect `/dev/mem` access

Edit Falco local rules file:

```
sudo vim /etc/falco/falco_rules.local.yaml
```

Add the following rule:

```yaml
- list: sensitive_devices
  items: [/dev/mem]

- rule: Container Accesses /dev/mem
  desc: Detect containers attempting to read or write /dev/mem
  condition: >
    evt.type in (open, openat, openat2) and fd.name in (sensitive_devices)
  output: >
    container_id=%container.id 
  priority: CRITICAL
```

Save and exit.

---

### Step 3: Run Falco using the local rules

Run Falco in the foreground so you can immediately see events:

```
sudo falco -r /etc/falco/falco_rules.local.yaml
```

When the suspicious access happens, Falco will print an alert including:

* `container_id`
* Kubernetes namespace
* Pod name (often available as `k8s.pod`)
* Container name

Example (illustration):

```
Suspicious /dev/mem access ... container_id=abcd1234 k8s.ns=neuron k8s.pod=neuron-xxx
```

---

### Step 4: Map container ID to Pod/Deployment (if needed)

If Falco output includes the Pod name already, you can skip this step.

Otherwise, use CRI tooling to identify the container:

```
sudo crictl ps | grep <container-id>
```

Then find the Pod and Deployment via Kubernetes labels:

```
kubectl get pod -n neuron -o wide
kubectl describe pod -n neuron <pod-name>
```

---

### Step 5: Scale the Deployment down to 0 replicas

Once you identify the Deployment, scale it down:

```
kubectl scale deployment -n neuron <deployment-name> --replicas=0
```

Verify:

```
kubectl get deploy,pods -n neuron
```

Pods for that Deployment should terminate.

</details>

---

# ↩️ Restore Cluster State


<details>
<summary>Click to expand setup steps</summary>


| `reset_q05_baseline.sh` | Moving to next problem? Removes namespace and fully uninstalls Falco |

---

### 🧹 Script : reset_q05_baseline.sh
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q05: Detecting a Pod Accessing /dev/mem
# reset_to_baseline.sh
# Removes neuron namespace and fully uninstalls Falco
# Run on: controlplane node
# ============================================================

set -euo pipefail

NAMESPACE="neuron"

echo ""
echo "==========================================="
echo " CKS Q05 — Restoring cluster to baseline..."
echo "==========================================="
echo ""

# ── Step 1: Delete neuron namespace ──────────────────────────
echo "[1/3] Deleting namespace '$NAMESPACE'..."

kubectl delete namespace "$NAMESPACE" --ignore-not-found
echo "  Namespace and all workloads removed."

# ── Step 2: Stop Falco service ────────────────────────────────
echo "[2/3] Stopping and uninstalling Falco..."

sudo systemctl stop falco 2>/dev/null || true
sudo systemctl disable falco 2>/dev/null || true

# Uninstall Falco package
sudo apt-get purge -y falco 2>/dev/null || true
sudo apt-get autoremove -y 2>/dev/null || true

# Remove Falco repo and keyring
sudo rm -f /etc/apt/sources.list.d/falcosecurity.list
sudo rm -f /usr/share/keyrings/falco-archive-keyring.gpg

# Remove Falco config directory
sudo rm -rf /etc/falco

sudo apt-get update -qq
echo "  Falco fully uninstalled."

# ── Step 3: Verify Falco removed ─────────────────────────────
echo "[3/3] Verifying Falco removal..."

if command -v falco &>/dev/null; then
    echo "  ⚠ WARNING: falco binary still found — may need manual cleanup."
else
    echo "  ✔ Falco binary not found — clean."
fi

echo ""
echo "✅ Cluster is back to baseline!"
echo ""
echo "   Safe to move to next problem. 🚀"
echo ""
```

</details>

---
