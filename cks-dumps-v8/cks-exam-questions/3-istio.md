# 🧩 Problem Statement(Istio mTLS Enforcement- Layer 4 Security)

<details>
<summary>Click to expand the problem statement</summary>


A microservices application is running in the Kubernetes cluster.
Currently, service-to-service communication within the application uses unencrypted **Layer 4 (TCP)** traffic.

Istio has already been installed in the cluster to help secure internal communication using **mutual TLS (mTLS)**.

The workloads are deployed inside the `istio-example` namespace, but secure communication is not yet fully enforced.

---

### 🎯 Task

To secure all Layer 4 traffic, complete the following:

1. Ensure every Pod running in the `istio-example` namespace has the **Istio sidecar proxy (`istio-proxy`) injected**.
2. Configure **mutual TLS authentication in STRICT mode** for all workloads inside the `istio-example` namespace.

---

### 📌 Notes

* Istio is already installed and available.
* You are allowed to refer to the official Istio documentation during the exam.
* After configuration, all internal service communication must use encrypted mTLS only.

</details>

---

# 🛠 Setup Practice Scenario

<details>
<summary>Click to expand setup steps</summary>


| Script | Purpose |
|--------|---------|
| `setup_q03_problem_scenario.sh` | Installs Istio and deploys workloads without mTLS — run before practice (re-run anytime to practice again) |

---

### 📥 Script: setup_q02_problem_scenario.sh
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q03: Istio mTLS Enforcement
# setup_problem_scenario.sh
# Installs Istio and deploys workloads without mTLS config
# Run on: controlplane node
# ============================================================

set -euo pipefail

ISTIO_NAMESPACE="istio-system"
APP_NAMESPACE="istio-example"

echo ""
echo "==========================================="
echo " CKS Q03 — Setting up Istio mTLS scenario..."
echo "==========================================="
echo ""

# ── Step 1: Tear down any previous Q03 state ─────────────────
echo "[1/5] Cleaning up any previous Q03 state..."

# Remove PeerAuthentication if user applied it previously
kubectl delete peerauthentication default -n "$APP_NAMESPACE" &>/dev/null || true
kubectl label namespace "$APP_NAMESPACE" istio-injection- &>/dev/null || true
kubectl rollout restart deploy -n "$APP_NAMESPACE" &>/dev/null || true

# Delete previous peer auth yaml files
rm -rf $HOME/*.yml
rm -rf $HOME/*.yaml

echo "  Previous state cleaned."

# ── Step 2: Install Istio (skip if already installed) ────────
echo "[2/5] Checking Istio installation..."

if kubectl get namespace "$ISTIO_NAMESPACE" &>/dev/null && \
   kubectl get pods -n "$ISTIO_NAMESPACE" --field-selector=status.phase=Running 2>/dev/null | grep -q istiod; then
    echo "  Istio already installed and running — skipping install."
else
    echo "  Installing Istio..."
    ISTIO_INSTALL_DIR="/tmp/cks-q03-istio"
    mkdir -p "$ISTIO_INSTALL_DIR"
    cd "$ISTIO_INSTALL_DIR"

    curl -L https://istio.io/downloadIstio | sh -

    # Find the downloaded istio directory
    ISTIO_DIR=$(ls -d istio-* | head -n 1)
    export PATH="$ISTIO_INSTALL_DIR/$ISTIO_DIR/bin:$PATH"

    istioctl install --set profile=demo -y

    echo "  Waiting for Istio control plane to be Ready..."
    kubectl wait --for=condition=ready pod \
        -l app=istiod -n "$ISTIO_NAMESPACE" --timeout=180s

    echo "  Istio installed successfully."
fi

# ── Step 3: Create namespace WITHOUT istio-injection label ────

if kubectl get deployment instagram -n "$APP_NAMESPACE" &>/dev/null; then
    echo "  Namespace and app already exist — skipping."
else
    echo "[3/5] Creating namespace $APP_NAMESPACE (no sidecar injection)..."

    kubectl create namespace "$APP_NAMESPACE"

    # Verify label is NOT present
    echo "  Namespace labels:"
    kubectl get ns "$APP_NAMESPACE" --show-labels | grep -v "istio-injection" && \
        echo "  ✔ istio-injection label is absent (as expected)" || true
    echo "  Namespace created."

    # ── Step 4: Deploy workloads (no sidecars at this point) ─────
    echo "[4/5] Deploying sample workloads..."

    kubectl create deployment instagram \
        -n "$APP_NAMESPACE" \
        --image=devopstechtales/cks-exam-questions:istio-v1

    kubectl create deployment tinder \
        -n "$APP_NAMESPACE" \
        --image=devopstechtales/cks-exam-questions:istio-v2

    echo "  Waiting for pods to be Running..."
    kubectl wait --for=condition=available deployment/instagram \
        -n "$APP_NAMESPACE" --timeout=120s
    kubectl wait --for=condition=available deployment/tinder \
        -n "$APP_NAMESPACE" --timeout=120s

fi

# ── Step 5: Verify no sidecar injected ───────────────────────
echo "[5/5] Verifying scenario state..."

CONTAINERS=$(kubectl get pods -n "$APP_NAMESPACE" \
    -o jsonpath='{.items[*].spec.containers[*].name}')

if echo "$CONTAINERS" | grep -q "istio-proxy"; then
    echo "  ⚠ WARNING: istio-proxy sidecar detected — scenario may not be clean."
else
    echo "  ✔ No istio-proxy sidecar present (as expected)."
fi

echo ""
echo "✅ Q03 scenario is ready!"
echo ""
echo "   Now Start Solution! 💪"
echo ""
```

</details>

---

# ✅ Solution

<details>
<summary>Click to expand the solution</summary>


In the CKS exam, you are allowed to access the official Istio documentation.
At the beginning of the question, a documentation link is usually provided — make sure to use it.

Reference:
[https://istio.io/latest/docs/reference/config/security/peer_authentication/](https://istio.io/latest/docs/reference/config/security/peer_authentication/)

---

### Step 1: Verify existing Pods

Check how many Pods are running inside the namespace:

```
kubectl get pods -n istio-example
```

---

### Step 2: Enable Istio Sidecar Injection

To inject the `istio-proxy` sidecar into all Pods in the namespace:

```
kubectl label namespace istio-example istio-injection=enabled
```

Verify label:

```
kubectl get ns istio-example --show-labels
```

---

### Step 3: Restart Deployments

Existing Pods will not automatically get sidecars.
You must restart the deployments:

```
kubectl rollout restart deployment -n istio-example
```

Verify sidecar injection:

```
kubectl get pods -n istio-example
```

You should now see **2 containers per Pod** (application + istio-proxy).

---

### Step 4: Enforce mTLS in STRICT Mode

Create a `PeerAuthentication` resource:

```yaml
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-example
spec:
  mtls:
    mode: STRICT
```

Apply it:

```
kubectl apply -f peerauth.yaml
```

Now all workloads in the namespace will only accept encrypted mTLS traffic.

</details>

---

# ↩️ Restore Cluster State


<details>
<summary>Click to expand setup steps</summary>


| `reset_q03_baseline.sh` | Moving to next problem? Run this to remove Istio and all Q03 changes |

### 🧹 Script : reset_q03_baseline.sh
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q03: Istio mTLS Enforcement
# reset_to_baseline.sh
# Removes all Q03 changes including Istio uninstall
# Run on: controlplane node
# ============================================================

set -euo pipefail

ISTIO_NAMESPACE="istio-system"
APP_NAMESPACE="istio-example"
ISTIO_INSTALL_DIR="/tmp/cks-q03-istio"

echo ""
echo "==========================================="
echo " CKS Q03 — Restoring cluster to baseline..."
echo "==========================================="
echo ""

# ── Step 1: Remove user-applied solution resources ───────────
echo "[1/4] Removing solution resources (if applied)..."

kubectl delete peerauthentication default \
    -n "$APP_NAMESPACE" --ignore-not-found
kubectl label namespace "$APP_NAMESPACE" \
    istio-injection- --ignore-not-found 2>/dev/null || true
echo "  PeerAuthentication and namespace label removed."

# ── Step 2: Delete application namespace ─────────────────────
echo "[2/4] Deleting $APP_NAMESPACE namespace..."

kubectl delete namespace "$APP_NAMESPACE" --ignore-not-found
echo "  Namespace deleted."

# ── Step 3: Uninstall Istio ───────────────────────────────────
echo "[3/4] Uninstalling Istio..."

if [ -d "$ISTIO_INSTALL_DIR" ]; then
    ISTIO_DIR=$(ls -d "$ISTIO_INSTALL_DIR"/istio-* 2>/dev/null | head -n 1)
    if [ -n "$ISTIO_DIR" ] && [ -f "$ISTIO_DIR/bin/istioctl" ]; then
        export PATH="$ISTIO_DIR/bin:$PATH"
        istioctl uninstall --purge -y
        echo "  Istio uninstalled via istioctl."
    else
        echo "  istioctl not found in $ISTIO_INSTALL_DIR — attempting kubectl cleanup..."
        kubectl delete namespace "$ISTIO_NAMESPACE" --ignore-not-found
    fi
else
    echo "  Istio install dir not found — attempting kubectl cleanup..."
    kubectl delete namespace "$ISTIO_NAMESPACE" --ignore-not-found
fi

# Remove Istio CRDs
kubectl get crd | grep istio.io | awk '{print $1}' | \
    xargs kubectl delete crd --ignore-not-found 2>/dev/null || true

kubectl delete namespace "$ISTIO_NAMESPACE" --ignore-not-found


# Cleanup temp files
rm -rf "$ISTIO_INSTALL_DIR"
rm -rf $HOME/*.yml
rm -rf $HOME/*.yaml
echo "  Istio CRDs and temp files cleaned."

# ── Step 4: Restart kubelet ───────────────────────────────────
echo "[4/4] Restarting kubelet..."
sudo systemctl daemon-reload
sudo systemctl restart kubelet
echo "  kubelet restarted."

echo ""
echo "✅ Cluster is back to baseline!"
echo ""
echo "   Safe to move to next problem. 🚀"
echo ""
```

</details>

---