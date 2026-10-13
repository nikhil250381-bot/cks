# 🧩 Problem Statement(BOM Tool)

<details>
<summary>Click to expand the problem statement</summary>

There is a Deployment named **`sbom`** running in the **`sbom`** namespace.

This Deployment contains **three containers**, and each container uses a **different image version**.

Your task is to inspect the container images and identify **which container includes** the package:

* `libcrypto3` **version** `3.1.4-r5`

After identifying the correct image version:

1. Use the pre-installed **`bom`** utility to generate an **SPDX (Software Bill of Materials)** report and save it as:

   ```
   ~/report.spdx
   ```
2. Update the **`sbom` Deployment** so that the container using the identified image version is **removed**.

The Deployment manifest file is located at:

```
~/sbom-deployment.yaml
```

---

### ✅ Important Constraints

* Do **not** modify the other containers.
* Only remove the container that uses the identified (Alpine-based) image version.

</details>

---

# 🛠 Setup Practice Scenario

<details>
<summary>Click to expand setup steps</summary>


| Script | Purpose |
|--------|---------|
| `setup_q06_problem_scenario.sh` | Creates sbom namespace, deploys 3-container workload, installs bom — run before practice (re-run anytime) |

---

### 📥 Script: setup_q06_problem_scenario.sh
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q06: BOM Tool (SBOM / SPDX)
# setup_problem_scenario.sh
# Deploys sbom workload with 3 containers + installs bom
# Run on: controlplane node
# ============================================================

set -euo pipefail

NAMESPACE="sbom"
MANIFEST_PATH="$HOME/sbom-deployment.yaml"

echo ""
echo "==========================================="
echo " CKS Q06 — Setting up BOM Tool scenario..."
echo "==========================================="
echo ""

# ── Step 1: Reset only deployment + user-generated files ─────
echo "[1/4] Cleaning up previous deployment and report files..."

kubectl delete deployment sbom -n "$NAMESPACE" --ignore-not-found
rm -f "$HOME/report.spdx" "$MANIFEST_PATH"

echo "  Previous state cleaned."

# ── Step 2: Install bom (skip if already installed) ───────────
echo "[2/4] Checking bom installation..."

if command -v bom &>/dev/null; then
    echo "  bom already installed — skipping."
else
    echo "  Installing bom..."
    curl -L https://github.com/kubernetes-sigs/bom/releases/latest/download/bom-amd64-linux \
        -o /tmp/bom
    chmod +x /tmp/bom
    sudo mv /tmp/bom /usr/local/bin/bom
    echo "  bom installed: $(bom version)"
fi

# ── Step 3: Ensure namespace exists + deploy workload ─────────
echo "[3/4] Ensuring namespace and deploying sbom workload..."

if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo "  Namespace '$NAMESPACE' already exists — skipping recreate."
else
    kubectl create namespace "$NAMESPACE"
    echo "  Namespace '$NAMESPACE' created."
fi

cat > "$MANIFEST_PATH" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sbom
  namespace: sbom
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sbom
  template:
    metadata:
      labels:
        app: sbom
    spec:
      containers:
      - name: container-1
        image: devopstechtales/cks-exam-questions:sbom-test-v1
        command: ["sleep", "3600"]
      - name: container-2
        image: devopstechtales/cks-exam-questions:sbom-test-v2
        command: ["sleep", "3600"]
      - name: container-3
        image: devopstechtales/cks-exam-questions:sbom-test-v3
        command: ["sleep", "3600"]
EOF

kubectl apply -f "$MANIFEST_PATH"

echo "  Waiting for pod to be Running..."
kubectl wait --for=condition=available deployment/sbom \
    -n "$NAMESPACE" --timeout=120s

# ── Step 4: Verify ────────────────────────────────────────────
echo "[4/4] Verifying scenario state..."
kubectl get pods -n "$NAMESPACE"
echo "  Manifest saved at: $MANIFEST_PATH"

echo ""
echo "✅ Q06 scenario is ready!"
echo ""
echo "Start the solution!"
echo ""
```

</details>

---

# ✅ Solution

<details>
<summary>Click to expand the solution</summary>

### Step 1: Identify the Pod name

Get the Pod running in the `sbom` namespace:

```
kubectl get pods -n sbom
```

Assume the Pod name is:

```
<POD_NAME>
```

---

### Step 2: Check which container has `libcrypto3` version `3.1.4-r5`

Run the following for each container:

```
kubectl exec -n sbom <POD_NAME> -c container-1 -- apk list --installed | grep libcrypto3
kubectl exec -n sbom <POD_NAME> -c container-2 -- apk list --installed | grep libcrypto3
kubectl exec -n sbom <POD_NAME> -c container-3 -- apk list --installed | grep libcrypto3
```

Example output:

```
container-1:
libcrypto3-3.3.0-r2 ...

container-2:
libcrypto3-3.1.4-r5 ...

container-3:
(no output)
```

So, **container-2** contains the target package version.

---

### Step 3: Generate SBOM (SPDX) using bom

Now generate the SPDX report for the identified image:

```
bom generate --image devopstechtales/cks-exam-questions:sbom-test-v2 -o ~/report.spdx
```

Verify the file exists:

```
ls -l ~/report.spdx
```

---

### Step 4: Remove the affected container from the Deployment

Edit the Deployment manifest:

```
vim ~/sbom-deployment.yaml
```

Remove only this container block:

```yaml
- name: container-2
  image: devopstechtales/cks-exam-questions:sbom-test-v2
  command: ["sleep", "3600"]
```

Save and apply the updated manifest:

```
kubectl apply -f ~/sbom-deployment.yaml
```

---

### Step 5: Verify the Deployment

Check Pods again:

```
kubectl get pods -n sbom
```

Optionally confirm the container list in the new Pod:

```
kubectl get pod -n sbom <NEW_POD_NAME> -o jsonpath='{.spec.containers[*].name}'; echo
```

You should now see only:

```
container-1 container-3
```

</details>

---

---

# ↩️ Restore Cluster State


<details>
<summary>Click to expand setup steps</summary>


| Script | Purpose |
|--------|---------|
| `reset_q06_baseline.sh` | Moving to next problem? Removes sbom namespace, manifest files and bom binary |

---

### 🧹 Script : reset_q06_baseline.sh
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q06: BOM Tool (SBOM / SPDX)
# reset_to_baseline.sh
# Removes sbom namespace, manifest files and bom binary
# Run on: controlplane node
# ============================================================

set -euo pipefail

NAMESPACE="sbom"

echo ""
echo "==========================================="
echo " CKS Q06 — Restoring cluster to baseline..."
echo "==========================================="
echo ""

# ── Step 1: Delete sbom namespace ────────────────────────────
echo "[1/3] Deleting namespace '$NAMESPACE'..."

kubectl delete namespace "$NAMESPACE" --ignore-not-found
echo "  Namespace and all resources removed."

# ── Step 2: Remove manifest and report files ─────────────────
echo "[2/3] Removing manifest and report files..."

sudo rm -f $HOME/sbom-deployment.yaml
sudo rm -f $HOME/report.spdx
echo "  Files removed."

# ── Step 3: Remove bom binary ────────────────────────────────
echo "[3/3] Removing bom binary..."

if command -v bom &>/dev/null; then
    sudo rm -f /usr/local/bin/bom
    echo "  bom binary removed."
else
    echo "  bom not found — skipping."
fi

echo ""
echo "✅ Cluster is back to baseline!"
echo ""
echo "   Safe to move to next problem. 🚀"
echo ""
```

</details>

---
