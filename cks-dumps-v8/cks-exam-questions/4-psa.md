# 🧩 Problem Statement(Restricted Pod Security Standard -PSA)

<details>
<summary>Click to expand the problem statement</summary>

A Kubernetes cluster is configured to enforce the **Restricted Pod Security Standard** across all user namespaces.

In the `restricted` namespace, an existing Deployment is not meeting the required Restricted security rules. Because of this, its Pods are being rejected and cannot be scheduled or started.

The Deployment manifest file is available at:

```
~/nginx-deployment.yaml
```

---

### 🎯 Task

* Update the Deployment in the `restricted` namespace so that it fully complies with the **Restricted Pod Security Standard**.
* After applying the required security settings, verify that the Pods are created and running successfully.

---

### 📌 Notes

* Modify only what is required for Restricted compliance.
* Ensure the workload can be scheduled and runs normally after the fix.

</details>

---

# 🛠 Setup Practice Scenario

<details>
<summary>Click to expand setup steps</summary>


| Script | Purpose |
|--------|---------|
| `setup_q04_problem_scenario.sh` | Creates namespace with PSA enforcement and non-compliant deployment — run before practice (re-run anytime) |

---

### 📥 Script : setup_q04_problem_scenario.sh
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q04: Restricted Pod Security Standard (PSA)
# setup_problem_scenario.sh
# Creates restricted namespace + non-compliant deployment
# Run on: controlplane node
# ============================================================
set -euo pipefail

NAMESPACE="restricted"
MANIFEST_FILE="$HOME/nginx-deployment.yaml"

MANIFEST_CONTENT='apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-unprivileged
  namespace: restricted
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginxinc/nginx-unprivileged
        ports:
        - containerPort: 80'

echo ""
echo "==========================================="
echo " CKS Q04 — Setting up PSA scenario..."
echo "==========================================="
echo ""

# ── Step 1: Reset deployment and manifest (always) ───────────
echo "[1/4] Cleaning up previous deployment and manifest..."

kubectl delete deployment nginx-unprivileged -n "$NAMESPACE" --ignore-not-found
rm -f "$MANIFEST_FILE"

echo "  Deployment and manifest cleared."

# ── Step 2: Ensure namespace exists with correct PSA label ───
echo "[2/4] Checking namespace..."

if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo "  Namespace '$NAMESPACE' already exists — skipping recreate."

    # Ensure PSA label is present (in case user removed it as part of solution)
    CURRENT_LABEL=$(kubectl get ns "$NAMESPACE" \
        -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || true)

    if [ "$CURRENT_LABEL" != "restricted" ]; then
        echo "  PSA label missing or changed — re-applying..."
        kubectl label namespace "$NAMESPACE" \
            pod-security.kubernetes.io/enforce=restricted --overwrite
    else
        echo "  PSA label enforce=restricted already set ✔"
    fi
else
    echo "  Creating namespace '$NAMESPACE' with enforce=restricted..."
    kubectl create namespace "$NAMESPACE"
    kubectl label namespace "$NAMESPACE" \
        pod-security.kubernetes.io/enforce=restricted
fi

echo "  Namespace labels:"
kubectl get ns "$NAMESPACE" --show-labels

# ── Step 3: Create non-compliant deployment manifest ─────────
echo "[3/4] Creating non-compliant nginx-deployment.yaml..."

cat > "$MANIFEST_FILE" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-unprivileged
  namespace: restricted
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginxinc/nginx-unprivileged
        ports:
        - containerPort: 80
EOF

echo "  nginx-deployment.yaml created at $MANIFEST_FILE"

# ── Step 4: Apply deployment (pods will be rejected by PSA) ──
echo "[4/4] Applying non-compliant deployment..."

kubectl apply -f "$MANIFEST_FILE"

sleep 5

POD_COUNT=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
EVENTS=$(kubectl get events -n "$NAMESPACE" \
    --sort-by=.lastTimestamp 2>/dev/null | tail -3)

echo ""
if [ "$POD_COUNT" -eq 0 ]; then
    echo "  ✔ No pods running — PSA is correctly blocking them."
else
    echo "  ⚠ WARNING: $POD_COUNT pod(s) running — PSA may not be enforcing."
fi

echo ""
echo "  Recent events:"
echo "$EVENTS"
echo ""
echo "✅ Q04 scenario is ready!"
echo ""
echo "  Start The Solution!"
echo ""
```

</details>


---

# ✅ Solution

<details>
<summary>Click to expand the solution</summary>

### Step 1: Check the Deployment status

Verify the Deployment in the `restricted` namespace:

```
kubectl get deploy -n restricted
```

If it shows `0/1` and no Pods are created, the Pod Security Admission policy is likely rejecting the Pod.

You can confirm by checking events:

```
kubectl get events -n restricted --sort-by=.lastTimestamp
```

---

### Step 2: Update the Deployment manifest

Edit the manifest file:

```
vim ~/nginx-deployment.yaml
```

Add the following `securityContext` at the **container level**:

```yaml
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault
```

Make sure it is placed under the container (example):

```yaml
spec:
  template:
    spec:
      containers:
      - name: nginx
        image: nginxinc/nginx-unprivileged
        ports:
        - containerPort: 80
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
          runAsNonRoot: true
          seccompProfile:
            type: RuntimeDefault
```

Save and exit.

---

### Step 3: Apply the updated manifest

```
kubectl apply -f ~/nginx-deployment.yaml
```

---

### Step 4: Verify Pods are running

```
kubectl get pods -n restricted
```

If the Pods are running normally, the Deployment now complies with the Restricted Pod Security Standard.

</details>

---

# ↩️ Restore Cluster State


<details>
<summary>Click to expand setup steps</summary>


| Script | Purpose |
|--------|---------|
| `reset_q04_baseline.sh` | Moving to next problem? Removes namespace and all Q04 resources |

---

### 🧹 Script : reset_q04_baseline.sh
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q04: Restricted Pod Security Standard (PSA)
# reset_to_baseline.sh
# Removes restricted namespace and all Q04 resources
# Run on: controlplane node
# ============================================================

set -euo pipefail

NAMESPACE="restricted"

echo ""
echo "==========================================="
echo " CKS Q04 — Restoring cluster to baseline..."
echo "==========================================="
echo ""

# ── Step 1: Delete namespace (removes deployment + pods) ─────
echo "[1/2] Deleting namespace '$NAMESPACE'..."

kubectl delete namespace "$NAMESPACE" --ignore-not-found
echo "  Namespace and all resources removed."

# ── Step 2: Remove manifest files ────────────────────────────
echo "[2/2] Removing nginx-deployment.yaml..."

sudo rm -f $HOME/nginx-deployment.yaml
echo "  Manifest files removed."

echo ""
echo "✅ Cluster is back to baseline!"
echo ""
echo "   Safe to move to next problem. 🚀"
echo ""
```

</details>

---
