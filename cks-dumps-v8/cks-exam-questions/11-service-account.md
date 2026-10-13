# 🧩 Problem Statement(Hardening ServiceAccount Token Usage)

<details>
<summary>Click to expand the problem statement</summary>

A security review found that a workload in the **`serviceaccount`** namespace is handling ServiceAccount tokens in a way that does not meet compliance requirements.

You must harden token usage for the existing monitoring components.

---

### 🎯 Tasks

1. Update the **ServiceAccount** `monitor-sa` in the `serviceaccount` namespace so that Kubernetes **does not automatically mount API credentials** into Pods using this ServiceAccount.

2. Update the **Deployment** `monitor` (in the same namespace) so that it still receives a ServiceAccount token, but **only through an explicitly defined projected volume**:

   * The projected volume must be named **`token`**
   * The token file must be mounted at:

     ```
     /var/run/secrets/kubernetes.io/serviceaccount/token
     ```
   * The mount must be **read-only**

Reference manifest:

```
~/monitor/deployment.yaml
```

</details>

---

# 🛠 Setup Practice Scenario

<details>
<summary>Click to expand setup steps</summary>



| Script | Purpose |
|--------|---------|
| `setup_q11_problem_scenario.sh` | Creates namespace, ServiceAccount and Deployment — run before practice (re-run anytime) |

---

### 📥 Script: setup_q11_problem_scenario.sh
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q11: Hardening ServiceAccount Token Usage
# Creates namespace, ServiceAccount and Deployment
# Run on: controlplane node
# ============================================================

set -euo pipefail

NAMESPACE="serviceaccount"
MANIFEST_DIR="$HOME/monitor"
MANIFEST_FILE="$MANIFEST_DIR/deployment.yaml"

echo ""
echo "==========================================="
echo " CKS Q11 — Setting up ServiceAccount scenario..."
echo "==========================================="
echo ""

# ── Step 1: Reset only user-modified state ───────────────────
echo "[1/4] Cleaning up previous Q11 state..."

# Deployment — user modifies this (automountServiceAccountToken)
kubectl delete deployment monitor -n "$NAMESPACE" --ignore-not-found

# ServiceAccount — user modifies this (automountServiceAccountToken)
kubectl delete serviceaccount monitor-sa -n "$NAMESPACE" --ignore-not-found

# Manifest dir — always restore to original non-hardened version
rm -rf "$MANIFEST_DIR"

echo "  Previous state cleaned."

# ── Step 2: Ensure namespace exists ──────────────────────────
echo "[2/4] Checking namespace..."

if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo "  Namespace '$NAMESPACE' already exists — skipping."
else
    kubectl create namespace "$NAMESPACE"
    echo "  Namespace '$NAMESPACE' created."
fi

# ── Step 3: Create ServiceAccount ────────────────────────────
echo "[3/4] Creating ServiceAccount monitor-sa..."

kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: monitor-sa
  namespace: $NAMESPACE
EOF

echo "  ServiceAccount monitor-sa created (automount: default true)."

# ── Step 4: Create manifest + apply Deployment ───────────────
echo "[4/4] Creating deployment manifest and applying..."

mkdir -p "$MANIFEST_DIR"

cat > "$MANIFEST_FILE" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: monitor
  namespace: serviceaccount
spec:
  replicas: 1
  selector:
    matchLabels:
      app: monitor
  template:
    metadata:
      labels:
        app: monitor
    spec:
      serviceAccountName: monitor-sa
      containers:
      - name: monitor
        image: nginx
        ports:
        - containerPort: 80
EOF

kubectl apply -f "$MANIFEST_FILE"

echo "  Waiting for deployment to be Ready..."
kubectl wait --for=condition=available deployment/monitor \
    -n "$NAMESPACE" --timeout=120s

echo ""
echo "✅ Q11 scenario is ready!"
echo ""
echo "Start the Solution!"
echo ""
```

</details>

---

# ✅ Solution

<details>
<summary>Click to expand the solution</summary>

You are allowed to refer to the official Kubernetes documentation if needed.

---

### Step 1: Disable Automatic Token Mounting

Edit the ServiceAccount:

```
kubectl edit serviceaccount monitor-sa -n serviceaccount
```

Add the following field:

```yaml
automountServiceAccountToken: false
```

Save and exit.

This prevents Kubernetes from automatically injecting API credentials into Pods using this ServiceAccount.

---

### Step 2: Update the Deployment

Open the Deployment manifest:

```
vim ~/monitor/deployment.yaml
```

Modify the Pod spec as follows:

```yaml
spec:
  serviceAccountName: monitor-sa
  automountServiceAccountToken: false
  containers:
  - name: monitor
    image: nginx
    ports:
    - containerPort: 80
    volumeMounts:
    - name: token
      mountPath: /var/run/secrets/kubernetes.io/serviceaccount/token
      readOnly: true
  volumes:
  - name: token
    projected:
      sources:
      - serviceAccountToken:
          path: token
          expirationSeconds: 3600
```

Save the file and apply it:

```
kubectl apply -f ~/monitor/deployment.yaml
```

Now the Pod will:

* Not receive automatically mounted credentials
* Receive a token only through the explicitly defined projected volume
* Mount it as read-only at the required path

</details>

---

# ↩️ Restore Cluster State


<details>
<summary>Click to expand setup steps</summary>


| Script | Purpose |
|--------|---------|
| `reset_q11_baseline.sh` | Removes namespace and manifest files |

---

### 🧹 Script: reset_q11_baseline.sh
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q11: Hardening ServiceAccount Token Usage
# Removes namespace and manifest files
# Run on: controlplane node
# ============================================================

set -euo pipefail

NAMESPACE="serviceaccount"

echo ""
echo "==========================================="
echo " CKS Q11 — Restoring cluster to baseline..."
echo "==========================================="
echo ""

# ── Step 1: Delete namespace ──────────────────────────────────
echo "[1/2] Deleting namespace '$NAMESPACE'..."

kubectl delete namespace "$NAMESPACE" --ignore-not-found
echo "  Namespace and all resources removed."

# ── Step 2: Remove manifest directory ────────────────────────
echo "[2/2] Removing $HOME/monitor directory..."


sudo rm -rf $HOME/monitor
echo "  $HOME/monitor directory removed."

echo ""
echo "✅ Cluster is back to baseline!"
echo ""
echo "   Safe to move to next problem. 🚀"
echo ""
```


</details>

---