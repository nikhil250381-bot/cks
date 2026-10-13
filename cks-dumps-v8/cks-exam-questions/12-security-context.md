# 🧩 Problem Statement(Container Security Context Hardening)

<details>
<summary>Click to expand the problem statement</summary>

A Kubernetes Deployment is running with insecure container settings.

Your objective is to harden the containers by enforcing immutability and reducing privilege-related risks.

An existing Deployment named **`secdep`** is deployed in the **`sec-ns`** namespace.

You have been provided with the manifest file:

```
~/sec-ns_deployment.yaml
```

---

### 🎯 Task

Update the Deployment so that all containers:

1. Run as a non-root user with **UID 32000**
2. Use a **read-only root filesystem**
3. **Disallow privilege escalation**

---

### 📌 Notes

* Modify the Deployment manifest file.
* Re-apply the updated manifest.
* Focus only on container-level security context settings required by the task.

</details>

---

# 🛠 Setup Practice Scenario

<details>
<summary>Click to expand setup steps</summary>


| Script | Purpose |
|--------|---------|
| `setup_q12_problem_scenario.sh` | Creates namespace + insecure Deployment + manifest file — run before practice (re-run anytime) |

---

### 📥 Script: setup_q12_problem_scenario.sh
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q12: Container Security Context Hardening
# Creates sec-ns namespace + insecure Deployment + manifest
# Run on: controlplane node
# ============================================================

set -euo pipefail

NAMESPACE="sec-ns"
MANIFEST_FILE="$HOME/sec-ns_deployment.yaml"

echo ""
echo "==========================================="
echo " CKS Q12 — Setting up Security Context scenario..."
echo "==========================================="
echo ""

# ── Step 1: Reset only user-modified state ───────────────────
echo "[1/3] Cleaning up previous Q12 state..."

# Deployment — user adds securityContext fields to this
kubectl delete deployment secdep -n "$NAMESPACE" --ignore-not-found

# Manifest — user edits this file directly
rm -f "$MANIFEST_FILE"

echo "  Previous state cleaned."

# ── Step 2: Ensure namespace exists ──────────────────────────
echo "[2/3] Checking namespace..."

if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo "  Namespace '$NAMESPACE' already exists — skipping."
else
    kubectl create namespace "$NAMESPACE"
    echo "  Namespace '$NAMESPACE' created."
fi

# ── Step 3: Create manifest + apply Deployment ───────────────
echo "[3/3] Creating manifest and deploying..."

cat > "$MANIFEST_FILE" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secdep
  namespace: sec-ns
spec:
  replicas: 1
  selector:
    matchLabels:
      app: secdep
  template:
    metadata:
      labels:
        app: secdep
    spec:
      containers:
      - name: nginx
        image: nginxinc/nginx-unprivileged
        ports:
        - containerPort: 80
        volumeMounts:
        - name: tmp
          mountPath: /tmp
        - name: cache
          mountPath: /var/cache/nginx
      volumes:
      - name: tmp
        emptyDir: {}
      - name: cache
        emptyDir: {}
EOF

kubectl apply -f "$MANIFEST_FILE"

echo "  Waiting for Deployment to be Ready..."
kubectl wait --for=condition=available deployment/secdep \
    -n "$NAMESPACE" --timeout=120s

echo ""
echo "✅ Q12 scenario is ready!"
echo ""
echo "Start the Solution!"
echo ""
```

</details>

---

# ✅ Solution

<details>
<summary>Click to expand the solution</summary>

### Step 1: Open the Deployment manifest

```
vim ~/sec-ns_deployment.yaml
```

---

### Step 2: Add securityContext at the container level

Inside the container specification, add:

```yaml
securityContext:
  runAsUser: 32000
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
```

Example:

```yaml
spec:
  containers:
  - name: nginx
    image: nginx:1.27
    ports:
    - containerPort: 80
    securityContext:
      runAsUser: 32000
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
```

⚠️ Important:

* It must be `securityContext` (lowercase `s`)
* It must be inside the container block

---

### Step 3: Apply the updated manifest

```
kubectl apply -f ~/sec-ns_deployment.yaml
```

---

### Step 4: Verify Pods

```
kubectl get pods -n sec-ns
```

Ensure the Pod restarts successfully with the updated configuration.

</details>

---

# ↩️ Restore Cluster State


<details>
<summary>Click to expand setup steps</summary>


| Script | Purpose |
|--------|---------|
| `reset_q12_baseline.sh` | Removes namespace and manifest files |

---

### 🧹 Script: reset_q12_baseline.sh
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q12: Container Security Context Hardening
# Removes sec-ns namespace and manifest files
# Run on: controlplane node
# ============================================================

set -euo pipefail

NAMESPACE="sec-ns"
MANIFEST_FILE="sec-ns_deployment.yaml"

echo ""
echo "==========================================="
echo " CKS Q12 — Restoring cluster to baseline..."
echo "==========================================="
echo ""

# ── Step 1: Delete namespace ──────────────────────────────────
echo "[1/2] Deleting namespace '$NAMESPACE'..."

kubectl delete namespace "$NAMESPACE" --ignore-not-found
echo "  Namespace and all resources removed."

# ── Step 2: Remove manifest files ────────────────────────────
echo "[2/2] Removing manifest files..."


rm -f "$HOME/$MANIFEST_FILE"
echo "  Manifest files removed."

echo ""
echo "✅ Cluster is back to baseline!"
echo ""
echo "   Safe to move to next problem. 🚀"
echo ""
```

</details>

---
