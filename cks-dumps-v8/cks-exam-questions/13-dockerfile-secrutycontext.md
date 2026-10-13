# 🧩 Problem Statement(🛡 Dockerfile & Deployment Hardening Review)

<details>
<summary>Click to expand the problem statement</summary>

A containerized application is prepared for deployment, but a security review identified poor practices in both:

* The Docker image configuration
* The Kubernetes deployment configuration

You must review and fix **one insecure instruction** in the Dockerfile and **one insecure field** in the Kubernetes manifest.

Dockerfile path:

```
~/cks/docker/Dockerfile
```

Kubernetes manifest path:

```
~/cks/docker/deployment.yaml
```

---

### ✅ Important Constraints

* Do **not** build the Docker image after making changes
* Do **not** add new configuration blocks
* Do **not** remove existing configuration sections
* Only **modify the insecure instruction or field**
* If a non-root user is required in Dockerfile, use:

  ```
  USER 65535
  ```

(the `nobody` user)

</details>

---

# 🛠 Setup Practice Scenario

<details>
<summary>Click to expand setup steps</summary>


| Script | Purpose |
|--------|---------|
| `setup_q13_problem_scenario.sh` | Creates insecure Dockerfile + manifest — run before practice (re-run anytime) |

---

### 📥 Script: setup_q13_problem_scenario.sh
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q13: Dockerfile & Deployment Hardening
# Creates insecure Dockerfile + deployment manifest
# Run on: controlplane node
# ============================================================

set -euo pipefail

CKS_DIR="$HOME/cks/docker"

echo ""
echo "==========================================="
echo " CKS Q13 — Setting up Hardening scenario..."
echo "==========================================="
echo ""

# ── Step 1: Clean previous Q16 state ─────────────────────────
echo "[1/3] Cleaning up any previous Q16 state..."

rm -rf "$HOME/cks"
echo "  Previous state cleaned."

# ── Step 2: Create insecure Dockerfile ───────────────────────
echo "[2/3] Creating insecure Dockerfile..."

mkdir -p "$CKS_DIR"

cat > "$CKS_DIR/Dockerfile" <<'EOF'
FROM nginx:1.27

LABEL maintainer="devops-team"

RUN apt-get update && \
    apt-get install -y curl && \
    rm -rf /var/lib/apt/lists/*

COPY ./html /usr/share/nginx/html

RUN chown -R root:root /usr/share/nginx/html

USER root

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
EOF

echo "  Dockerfile created (insecure: USER root)"

# ── Step 3: Create insecure deployment.yaml ───────────────────
echo "[3/3] Creating insecure deployment.yaml..."

cat > "$CKS_DIR/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secure-app
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: secure-app
  template:
    metadata:
      labels:
        app: secure-app
    spec:
      containers:
      - name: nginx
        image: nginxinc/nginx-unprivileged
        securityContext:
          privileged: true
          readOnlyRootFilesystem: false
          runAsUser: 0
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

echo "  deployment.yaml created (insecure: privileged=true, runAsUser=0)"

echo ""
echo "✅ Q13 scenario is ready!"
echo ""
echo "   Files:"
echo "   • $CKS_DIR/Dockerfile"
echo "   • $CKS_DIR/deployment.yaml"
echo ""
echo " Start the Solution!"
echo "   ⚠ Do NOT build the Docker image after changes."
echo ""
```

</details>

---
# ✅ Solution

<details>
<summary>Click to expand the solution</summary>

### Step 1: Fix the insecure Dockerfile instruction

Open the Dockerfile:

```
vim ~/cks/docker/Dockerfile
```

Change:

**From**

```
USER root
```

**To**

```
USER 65535
```

Save and exit.

⚠️ Do not build the image after this change.

---

### Step 2: Fix the insecure Kubernetes manifest field

Open the deployment manifest:

```
vim ~/cks/docker/deployment.yaml
```

Update only the existing `securityContext` fields:

**From**

```yaml
securityContext:
  privileged: true
  readOnlyRootFilesystem: false
  runAsUser: 0
```

**To**

```yaml
securityContext:
  privileged: false
  readOnlyRootFilesystem: true
  runAsUser: 65535
```

Save and exit.

</details>

---

# ↩️ Restore Cluster State


<details>
<summary>Click to expand setup steps</summary>


| Script | Purpose |
|--------|---------|
| `reset_q13_baseline.sh` | Removes ~/cks directory — run before moving to next problem |

---

### 🧹 Script: reset_q13_baseline.sh
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q16: Dockerfile & Deployment Hardening
# Removes ~/cks directory
# Run on: controlplane node
# ============================================================

set -euo pipefail

echo ""
echo "==========================================="
echo " CKS Q13 — Restoring to baseline..."
echo "==========================================="
echo ""

echo "[1/1] Removing ~/cks directory..."

rm -rf "$HOME/cks"
echo "  $HOME/cks removed."

echo ""
echo "✅ Cluster is back to baseline!"
echo ""
echo "   Safe to move to next problem. 🚀"
echo ""
```

</details>

---