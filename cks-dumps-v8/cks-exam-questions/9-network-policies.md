# 🧩 Problem Statement(Network Policy)

<details>
<summary>Click to expand the problem statement</summary>

You are working in a Kubernetes cluster where multiple namespaces host different application components.
To improve security, inter-namespace network communication must be controlled using **NetworkPolicies**.

---

### ✅ Requirements

1. In the **`production`** namespace, create a NetworkPolicy named **`deny-policy`** that **blocks all incoming traffic** to Pods by default.

   The `production` namespace has the label:

   ```
   env: production
   ```

2. In the **`database`** namespace, create a NetworkPolicy named **`allow-from-production`** that **permits ingress traffic only from Pods running in the production namespace**.

   * Use the **namespace label** to allow traffic.
   * The `database` namespace has the label:

     ```
     env: database
     ```

---

### 📌 Note

* Do **not** modify any Deployments.

</details>

---

# 🛠 Setup Practice Scenario

<details>
<summary>Click to expand setup steps</summary>


| Script | Purpose |
|--------|---------|
| `setup_q09_problem_scenario.sh` | Creates namespaces with labels, ensures Calico is installed — run before practice (re-run anytime) |

---

### 📥 Script : setup_q09_problem_scenario.sh
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q09: Network Policy
# Creates production + database namespaces with labels
# Run on: controlplane node
# ============================================================

set -euo pipefail

echo ""
echo "==========================================="
echo " CKS Q09 — Setting up Network Policy scenario..."
echo "==========================================="
echo ""

# ── Step 1: Clean previous Q09 state ─────────────────────────
echo "[1/3] Cleaning up any previous Q09 state..."

kubectl delete networkpolicy deny-policy \
    -n production --ignore-not-found
kubectl delete networkpolicy allow-from-production \
    -n database --ignore-not-found

echo "  Previous NetworkPolicies cleaned."

# ── Step 2: Verify CNI is running (supports NetworkPolicy) ───
echo "[2/3] Checking CNI..."

if kubectl get pods -n kube-system --no-headers 2>/dev/null \
        | grep -Ei "calico|cilium|weave|flannel" \
        | grep -q Running; then
    CNI=$(kubectl get pods -n kube-system --no-headers 2>/dev/null \
        | grep -Ei "calico|cilium|weave|flannel" \
        | grep Running | head -1 | awk '{print $1}')
    echo "  CNI already running ($CNI) — skipping install. ✔"
else
    echo "  ⚠ WARNING: No CNI detected in kube-system."
    echo "  NetworkPolicy enforcement may not work."
    echo "  Please ensure a CNI is installed before proceeding."
fi

# ── Step 3: Create namespaces with labels ────────────────────
echo "[3/3] Creating namespaces..."

# production namespace
if kubectl get namespace production &>/dev/null; then
    echo "  production namespace already exists — ensuring label..."
else
    kubectl create namespace production
    echo "  production namespace created."
fi
kubectl label namespace production env=production --overwrite
echo "  production → label env=production ✔"

# database namespace
if kubectl get namespace database &>/dev/null; then
    echo "  database namespace already exists — ensuring label..."
else
    kubectl create namespace database
    echo "  database namespace created."
fi
kubectl label namespace database env=database --overwrite
echo "  database → label env=database ✔"

echo ""
echo "✅ Q09 scenario is ready!"
echo ""
echo "Start the Solution!"
echo ""
```

</details>

---

# ✅ Solution

<details>
<summary>Click to expand the solution</summary>

You may refer to the Kubernetes NetworkPolicy documentation if needed.

---

### 1) deny-policy (block all ingress in production)

This policy selects **all Pods** in the `production` namespace and blocks ingress by default.

```
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-policy
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF
```

---

### 2) allow-from-production (allow ingress only from production namespace)

This policy selects **all Pods** in the `database` namespace and allows ingress only from namespaces labeled `env=production`.

```
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-production
  namespace: database
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          env: production
EOF
```



---

### 🧪 Optional Validation

Create test Pods:

```
kubectl run prod-pod --image=nginx -n production
kubectl run db-pod --image=nginx -n database
kubectl run default-pod --image=busybox -n default -- sleep 3600
```

Get the DB Pod IP:

```
DB_IP=$(kubectl get pod db-pod -n database -o jsonpath='{.status.podIP}')
echo $DB_IP
```

Test access from production (should be allowed):

```
kubectl exec -n production prod-pod -- curl -m 5 http://$DB_IP
```

Test access from default namespace (should be blocked):

```
kubectl exec -n default default-pod -- wget -T 5 -qO- http://$DB_IP
```

Cleanup:

```
kubectl delete pod prod-pod -n production
kubectl delete pod db-pod -n database
kubectl delete pod default-pod -n default
```

</details>

---

# ↩️ Restore Cluster State

<details>
<summary>Click to expand setup steps</summary>


| Script | Purpose |
|--------|---------|
| `reset_q09_baseline.sh` | Removes namespaces and all Q09 resources |

---

### 🧹 Script : reset_q09_baseline.sh
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q09: Network Policy
# Removes production + database namespaces and all Q09 resources
# Run on: controlplane node
# ============================================================

set -euo pipefail

echo ""
echo "==========================================="
echo " CKS Q09 — Restoring cluster to baseline..."
echo "==========================================="
echo ""

# ── Step 1: Delete namespaces (removes NPs + all resources) ──
echo "[1/1] Deleting production and database namespaces..."

kubectl delete namespace production --ignore-not-found
kubectl delete namespace database --ignore-not-found
echo "  Namespaces and all resources removed."

echo ""
echo "✅ Cluster is back to baseline!"
echo "   Safe to move to next problem. 🚀"
echo ""
```

</details>

---
