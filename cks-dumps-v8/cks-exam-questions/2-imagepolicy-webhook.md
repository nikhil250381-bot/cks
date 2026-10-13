# 🧩 Problem Statement(ImagePolicyWebhook)

<details>
<summary>Click to expand the problem statement</summary>

A Kubernetes cluster built using **kubeadm** must enforce strict container image security controls.

An image scanning service is already running in the cluster and exposes an HTTPS webhook endpoint to validate images before they are allowed to run.

An incomplete admission controller configuration is provided at:

```bash
/etc/kubernetes/webhook/
```

The image scanning webhook is reachable at:

```bash
https://image-policy-webhook.default
```

---

### 🎯 Task

Complete the integration of container image validation by implementing an **ImagePolicyWebhook Validating Admission Controller**.

1. Update the Kubernetes API server configuration so the required admission plugin is enabled and uses the provided AdmissionConfiguration.
2. Configure ImagePolicyWebhook to operate in **fail-closed** mode (reject images if the webhook backend is unavailable).
3. Verify the setup by deploying the test workload:

```bash
~/nginx-deployment.yaml
```

This workload uses an image that should be denied by the policy. You may delete and recreate it as needed.

---

### 📌 Notes

* Apply changes on the **control plane node**.
* Ensure the admission controller is functioning correctly before finishing.

</details>

---

# 🛠 Setup Practice Scenario

<details>
<summary>Click to expand setup steps</summary>



| Script | Purpose |
|--------|---------|
| `setup_q02_problem_scenario.sh` | Deploys webhook infrastructure with incomplete config — run before practice (re-run anytime to practice again) |


---

### 📥 Script : setup_q02_problem_scenario.sh

Run this **before you start practicing** this problem.
Re-run anytime you want to practice again after fixing.
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q02: ImagePolicyWebhook
# setup_problem_scenario.sh
# Deploys webhook infra with intentionally incomplete config
# Run on: controlplane node
# ============================================================

set -euo pipefail

WEBHOOK_DIR="/etc/kubernetes/webhook"
APISERVER_MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"
WORK_DIR="/tmp/cks-q02-setup"

echo ""
echo "==========================================="
echo " CKS Q02 — Setting up ImagePolicyWebhook scenario..."
echo "==========================================="
echo ""

# ── Step 1: Install cfssl ─────────────────────────────────────
echo "[1/8] Installing cfssl..."
sudo apt-get install -y golang-cfssl -qq
echo "  cfssl installed."

# ── Step 2: Generate server key + CSR ────────────────────────
echo "[2/8] Generating server key and CSR..."
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

CONTROL_PLANE_IP=$(kubectl get nodes --selector='node-role.kubernetes.io/control-plane' \
  -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

CLUSTER_DNS_IP=$(kubectl get svc kube-dns -n kube-system \
  -o jsonpath='{.spec.clusterIP}')

cat <<EOF | cfssl genkey - | cfssljson -bare server
{
  "hosts": [
    "image-policy-webhook",
    "image-policy-webhook.default",
    "image-policy-webhook.default.svc",
    "image-policy-webhook.default.svc.cluster.local",
    "${CLUSTER_DNS_IP}",
    "${CONTROL_PLANE_IP}",
    "10.32.0.1"
  ],
  "CN": "system:node:image-policy-webhook.default.pod.cluster.local",
  "key": {
    "algo": "ecdsa",
    "size": 256
  },
  "names": [
    {
      "O": "system:nodes"
    }
  ]
}
EOF
echo "  Key and CSR generated."

# ── Step 3: Create + approve K8s CSR ─────────────────────────
echo "[3/8] Submitting and approving Kubernetes CSR..."

kubectl delete csr image-policy-webhook --ignore-not-found

cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: image-policy-webhook
spec:
  request: $(cat server.csr | base64 | tr -d '\n')
  signerName: kubernetes.io/kubelet-serving
  usages:
  - digital signature
  - key encipherment
  - server auth
EOF

kubectl certificate approve image-policy-webhook
sleep 3
kubectl get csr image-policy-webhook \
  -o jsonpath='{.status.certificate}' | base64 --decode > tls.crt
cp server-key.pem tls.key
echo "  TLS cert approved and saved."

# ── Step 4: Create TLS secret ─────────────────────────────────
echo "[4/8] Creating TLS secret in default namespace..."

kubectl -n default delete secret image-policy-webhook-tls --ignore-not-found
kubectl -n default create secret tls image-policy-webhook-tls \
  --cert=tls.crt \
  --key=tls.key
echo "  TLS secret created."

# ── Step 5: Deploy webhook server ────────────────────────────

echo "[5/8] Deploying webhook Deployment and Service..."

kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: image-policy-webhook
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: image-policy-webhook
  template:
    metadata:
      labels:
        app: image-policy-webhook
    spec:
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      containers:
      - name: webhook
        image: devopstechtales/cks-exam-questions:image-policy-webhook-v1
        ports:
        - containerPort: 443
        volumeMounts:
        - name: tls
          mountPath: /tls
          readOnly: true
      volumes:
      - name: tls
        secret:
          secretName: image-policy-webhook-tls
---
apiVersion: v1
kind: Service
metadata:
  name: image-policy-webhook
  namespace: default
spec:
  type: NodePort
  selector:
    app: image-policy-webhook
  ports:
  - name: https
    port: 443
    targetPort: 443
    nodePort: 32000
    protocol: TCP
EOF

echo "  Waiting for webhook pod to be Ready..."
kubectl wait --for=condition=ready pod \
  -l app=image-policy-webhook -n default --timeout=120s
echo "  Webhook pod is Ready."

# ── Step 6: Create webhook config files ──────────────────────
echo "[6/8] Creating config files at $WEBHOOK_DIR..."

sudo mkdir -p "$WEBHOOK_DIR"
sudo cp tls.crt "$WEBHOOK_DIR/tls.crt"

# AdmissionConfiguration — references the ImagePolicy config
sudo tee "$WEBHOOK_DIR/admission-config.yml" >/dev/null <<'EOF'
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
- name: ImagePolicyWebhook
  path: image-policy-config.yml
EOF

# ⚠ defaultAllow: true (fail-open) — user must change to false
sudo tee "$WEBHOOK_DIR/image-policy-config.yml" >/dev/null <<'EOF'
imagePolicy:
  kubeConfigFile: /etc/kubernetes/webhook/kube-config.yml
  allowTTL: 50
  denyTTL: 50
  retryBackoff: 500
  defaultAllow: true
EOF

# ⚠ server: intentionally left empty — user must fill in
sudo tee "$WEBHOOK_DIR/kube-config.yml" >/dev/null <<'EOF'
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority: /etc/kubernetes/webhook/tls.crt
    server: 
  name: image-policy-webhook
contexts:
- context:
    cluster: image-policy-webhook
    user: api-server
  name: image-policy-webhook
current-context: image-policy-webhook
users:
- name: api-server
  user:
    client-certificate: /etc/kubernetes/pki/apiserver.crt
    client-key: /etc/kubernetes/pki/apiserver.key
EOF
echo "  Config files created."

# ── Step 7: Patch kube-apiserver manifest ────────────────────
echo "[7/8] Patching kube-apiserver (volume + mount + config flag + dns)..."

sudo python3 - <<PYEOF
import yaml

manifest_path = "/etc/kubernetes/manifests/kube-apiserver.yaml"

with open(manifest_path, "r") as f:
    manifest = yaml.safe_load(f)

spec = manifest["spec"]
container = spec["containers"][0]
args = container.get("command", [])

# ── Strip ImagePolicyWebhook + old config-file flag first ──────
cleaned_args = []
for a in args:
    if a.startswith("--enable-admission-plugins="):
        prefix, _, values = a.partition("=")
        plugins = [p.strip() for p in values.split(",") if p.strip() != "ImagePolicyWebhook"]
        cleaned_args.append(f"--enable-admission-plugins={','.join(plugins)}")
    elif "admission-control-config-file" in a:
        pass  # drop old entry, we re-add fresh below
    else:
        cleaned_args.append(a)

# ── Now append config-file flag onto cleaned_args ──────────────
config_flag = "--admission-control-config-file=/etc/kubernetes/webhook/admission-config.yml"
cleaned_args.append(config_flag)

container["command"] = cleaned_args  # ← single assignment, no overwrite

# Add volumeMount
mounts = container.get("volumeMounts", [])
if not any(m.get("name") == "webhook-config" for m in mounts):
    mounts.append({
        "mountPath": "/etc/kubernetes/webhook",
        "name": "webhook-config",
        "readOnly": True
    })
container["volumeMounts"] = mounts

# Add volume
volumes = spec.get("volumes", [])
if not any(v.get("name") == "webhook-config" for v in volumes):
    volumes.append({
        "name": "webhook-config",
        "hostPath": {
            "path": "/etc/kubernetes/webhook",
            "type": "DirectoryOrCreate"
        }
    })
spec["volumes"] = volumes

# Add dnsPolicy + dnsConfig
spec["dnsPolicy"] = "ClusterFirstWithHostNet"
spec["dnsConfig"] = {
    "nameservers": ["${CLUSTER_DNS_IP}"],
    "searches": ["default.svc.cluster.local", "svc.cluster.local"]
}

with open(manifest_path, "w") as f:
    yaml.dump(manifest, f, default_flow_style=False)

print("  kube-apiserver manifest patched.")
PYEOF

# ── Step 8: Create test workload ──────────────────────────────
echo "[8/8] Creating ~/nginx-deployment.yaml..."

# Create test workload in both home directories
cat <<'EOF' | tee $HOME/nginx-deployment.yaml > /dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: default
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
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      containers:
      - name: nginx
        image: nginx
        ports:
        - containerPort: 80
EOF

# Fix ownership for ubuntu user
sudo chown $(id -u):$(id -u) $HOME/nginx-deployment.yaml
echo "  $HOME/nginx-deployment.yaml created for current user $(whoami)."


sudo systemctl daemon-reload
sudo systemctl restart kubelet

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
echo "✅ Q02 scenario is ready!"
echo ""
echo "   Now go fix them! 💪"
echo ""
```

</details>


---

# ✅ Solution

<details>
<summary>Click to expand the solution</summary>

### Step 1: Update ImagePolicyWebhook config (fail-closed)

Go to the webhook config directory (based on your setup):

```
cd /etc/kubernetes/webhook/
```

Edit:

```
sudo vim image-policy-config.yml
```

Change:

**From**

```yaml
defaultAllow: true
```

**To**

```yaml
defaultAllow: false
```

This enables **fail-closed** behavior.

---

### Step 2: Add webhook server details in kubeconfig

Edit:

```
sudo vim kube-config.yml
```

Set the `server:` field to the webhook endpoint:

```yaml
server: https://image-policy-webhook.default
```

✅ Make sure the hostname and port are correct for your environment.

---

### Step 3: Enable ImagePolicyWebhook in kube-apiserver

Edit the kube-apiserver static Pod manifest:

```
sudo vim /etc/kubernetes/manifests/kube-apiserver.yaml
```

Ensure the following flags are present:

```yaml
- --enable-admission-plugins=ImagePolicyWebhook
- --admission-control-config-file=/etc/kubernetes/webhook/admission-config.yml
```

> Note: Sometimes `--enable-admission-plugins` already exists with multiple plugins.
> If so, **append** `ImagePolicyWebhook` instead of overwriting the list.

---

### Step 4: Restart kubelet (apiserver restarts automatically)

```
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

---

### Step 5: Test by deploying the workload

```
kubectl apply -f ~/nginx-deployment.yaml
```

If configured correctly, the Pod should be denied and not created.

Check resources:

```
kubectl get deploy,rs,pods
```

Describe the ReplicaSet to confirm webhook denial:

```
kubectl describe rs <rs-name>
```

Expected event example:

```
Warning  FailedCreate  ...  replicaset-controller  Error creating: pods "nginx-..." is forbidden:
image policy webhook backend denied one or more images: denied: image tag is missing (implicit latest is not allowed)
```

</details>

---

# ↩️ Restore Cluster State


<details>
<summary>Click to expand setup steps</summary>



| Script | Purpose |
|--------|---------|
| `reset_q02_baseline.sh` | Moving to next problem? Run this to remove all Q02 changes and restore clean cluster state |

---

### 🧹 Script : reset_q02_baseline.sh

**Done with this problem? Moving to the next one?**
Run this to remove all Q02 changes and restore a clean cluster state.
```bash
#!/bin/bash
# ============================================================
# CKS Practice | Q02: ImagePolicyWebhook
# reset_to_baseline.sh
# ============================================================

set -euo pipefail

WEBHOOK_DIR="/etc/kubernetes/webhook"
APISERVER_MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"
WORK_DIR="/tmp/cks-q02-setup"

echo ""
echo "==========================================="
echo " CKS Q02 — Restoring cluster to baseline..."
echo "==========================================="
echo ""

# ── Step 1: Remove K8s resources FIRST (apiserver still up) ───
echo "[1/4] Removing webhook Deployment, Service, Secret, and CSR..."

kubectl delete deployment image-policy-webhook -n default --ignore-not-found
kubectl delete service    image-policy-webhook -n default --ignore-not-found
kubectl delete secret     image-policy-webhook-tls -n default --ignore-not-found
kubectl delete csr        image-policy-webhook --ignore-not-found
kubectl delete deploy -n default --all --ignore-not-found
echo "  K8s resources removed."

# ── Step 2: Patch kube-apiserver manifest ─────────────────────
echo "[2/4] Removing Q02 changes from kube-apiserver manifest..."

sudo python3 - <<'PYEOF'
import yaml

manifest_path = "/etc/kubernetes/manifests/kube-apiserver.yaml"

with open(manifest_path, "r") as f:
    manifest = yaml.safe_load(f)

spec = manifest["spec"]
container = spec["containers"][0]
args = container.get("command", [])

cleaned_args = []
for a in args:
    if a.startswith("--enable-admission-plugins="):
        prefix, _, values = a.partition("=")
        plugins = [p.strip() for p in values.split(",") if p.strip() != "ImagePolicyWebhook"]
        cleaned_args.append(f"--enable-admission-plugins={','.join(plugins)}")
    elif "admission-control-config-file" in a:
        pass  # remove entirely
    else:
        cleaned_args.append(a)
container["command"] = cleaned_args

# Remove webhook volumeMount
mounts = container.get("volumeMounts", [])
container["volumeMounts"] = [m for m in mounts if m.get("name") != "webhook-config"]

# Remove webhook volume
volumes = spec.get("volumes", [])
spec["volumes"] = [v for v in volumes if v.get("name") != "webhook-config"]

# Remove dnsPolicy and dnsConfig
spec.pop("dnsPolicy", None)
spec.pop("dnsConfig", None)

with open(manifest_path, "w") as f:
    yaml.dump(manifest, f, default_flow_style=False)

print("  kube-apiserver manifest cleaned.")
PYEOF

# ── Step 3: Remove config files and work dir ──────────────────
echo "[3/4] Removing webhook config directory and temp files..."

sudo rm -rf "$WEBHOOK_DIR"
rm -rf "$WORK_DIR"
sudo rm -f $HOME/nginx-deployment.yaml
echo "  Files cleaned up."

# ── Step 4: Restart kubelet ───────────────────────────────────
echo "[4/4] Restarting kubelet..."
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
