# 🧩 Problem Statement(Creating a TLS Secret for an Existing Web Deployment)

<details>
<summary>Click to expand the problem statement</summary>

A Kubernetes web application is already running in the cluster, but secure HTTPS access has not been configured.

To enable encrypted communication, SSL certificate and private key files are available on the node. These must be stored inside Kubernetes as a **TLS Secret**.

---

### 🎯 Task

Create a TLS Secret named **`bright-banyan`** in the **`bright-banyan`** namespace.

The Secret must be created using the following SSL files:

* Certificate file:
  `/root/tls/banyan.crt`

* Private key file:
  `/root/tls/banyan.key`

An existing Deployment named **`bright-banyan`** is already configured to reference this Secret.

---

### 📌 Important Notes

* ❌ Do NOT modify the Deployment.
* ✅ Only create the required TLS Secret.
* ✅ Ensure the Secret type is `kubernetes.io/tls`.
* ✅ Create it in the correct namespace.

</details>

---

# 🛠 Setup Practice Scenario

<details>
<summary>Click to expand setup steps</summary>


| Script | Purpose |
|--------|---------|
| `setup_q14_problem_scenario.sh` | Creates TLS files, namespace and Deployment — run before practice (re-run anytime) |

---

### 📥 Script 1: setup_problem_scenario.sh
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q14: Creating a TLS Secret
# Creates TLS files, namespace and Deployment
# Run on: controlplane node
# ============================================================

set -euo pipefail

NAMESPACE="bright-banyan"
TLS_DIR="$HOME/tls"

echo ""
echo "==========================================="
echo " CKS Q14 — Setting up TLS Secret scenario..."
echo "==========================================="
echo ""

# ── Step 1: Reset only user-modified state ───────────────────
echo "[1/3] Cleaning up previous Q14 state..."

# TLS secret — user creates this as the solution
kubectl delete secret bright-banyan -n "$NAMESPACE" --ignore-not-found

# Force pod restart so it tries to mount missing secret → goes 0/1 Pending
kubectl rollout restart deployment bright-banyan \
    -n "$NAMESPACE" &>/dev/null || true

# TLS dir — always regenerate fresh cert/key
rm -rf "$TLS_DIR"

echo "  Previous state cleaned."

# ── Step 2: Generate TLS cert + key ──────────────────────────
echo "[2/3] Generating TLS certificate and key..."

mkdir -p "$TLS_DIR"

openssl req -x509 -nodes -days 365 \
    -newkey rsa:2048 \
    -keyout "$TLS_DIR/banyan.key" \
    -out "$TLS_DIR/banyan.crt" \
    -subj "/CN=web.k8s.local" 2>/dev/null

echo "  TLS files created:"
echo "  • $TLS_DIR/banyan.crt"
echo "  • $TLS_DIR/banyan.key"

# ── Step 3: Ensure namespace + Deployment exist ───────────────
echo "[3/3] Checking namespace and Deployment..."

if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo "  Namespace '$NAMESPACE' already exists — skipping."
else
    kubectl create namespace "$NAMESPACE"
    echo "  Namespace '$NAMESPACE' created."
fi

if kubectl get deployment bright-banyan -n "$NAMESPACE" &>/dev/null; then
    echo "  Deployment 'bright-banyan' already exists — skipping."
else
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bright-banyan
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: bright-banyan
  template:
    metadata:
      labels:
        app: bright-banyan
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        ports:
        - containerPort: 443
        volumeMounts:
        - name: tls-cert
          mountPath: /etc/nginx/tls
          readOnly: true
      volumes:
      - name: tls-cert
        secret:
          secretName: bright-banyan
EOF
    echo "  Deployment bright-banyan created."
fi

echo "  (Pod stays Pending — secret does not exist yet) ✔"

echo ""
echo "✅ Q14 scenario is ready!"
echo ""
echo "Start the Solution!"
echo ""
```

</details>

---

# ✅ Solution

<details>
<summary>Click to expand the solution</summary>

### Step 1: Verify Deployment Status

Check whether the Deployment exists and its current status:

```
kubectl get deployment -n bright-banyan
```

You may see `0/1` READY because the required Secret does not exist yet.

---

### Step 2: Create the TLS Secret

Use the provided certificate and key files:

```
kubectl create secret tls bright-banyan \
  -n bright-banyan \
  --cert=/root/tls/banyan.crt \
  --key=/root/tls/banyan.key
```

This automatically creates a Secret of type:

```
kubernetes.io/tls
```

---

### Step 3: Verify Secret

```
kubectl get secret bright-banyan -n bright-banyan
```

Optional detailed check:

```
kubectl describe secret bright-banyan -n bright-banyan
```

---

### Step 4: Verify Deployment Status

```
kubectl get deployment -n bright-banyan
```

The Deployment should now show:

```
1/1 READY
```

This confirms the Secret was created correctly and mounted successfully.

</details>

---

# ↩️ Restore Cluster State


<details>
<summary>Click to expand setup steps</summary>


| Script | Purpose |
|--------|---------|
| `reset_q14_baseline.sh` | Removes namespace and TLS files |

---

### 🧹 Script: reset_q14_baseline.sh
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q14: Creating a TLS Secret
# Removes namespace and TLS files
# Run on: controlplane node
# ============================================================

set -euo pipefail

NAMESPACE="bright-banyan"
TLS_DIR="$HOME/tls"

echo ""
echo "==========================================="
echo " CKS Q14 — Restoring cluster to baseline..."
echo "==========================================="
echo ""

# ── Step 1: Delete namespace ──────────────────────────────────
echo "[1/2] Deleting namespace '$NAMESPACE'..."

kubectl delete namespace "$NAMESPACE" --ignore-not-found
echo "  Namespace and all resources removed."

# ── Step 2: Remove TLS files ──────────────────────────────────
echo "[2/2] Removing TLS files..."

rm -rf "$TLS_DIR"
echo "  $TLS_DIR removed."

echo ""
echo "✅ Cluster is back to baseline!"
echo ""
echo "   Safe to move to next problem. 🚀"
echo ""
```

</details>

---
