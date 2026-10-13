# 🚀 Provisioning a kubeadm Cluster on AWS (1 Control Plane + 1 Worker)

This guide explains how to provision a Kubernetes cluster on AWS using:

* 1 Control Plane node
* 1 Worker node
* kubeadm
* Calico CNI

All infrastructure is provisioned using the provided automation scripts.

---

## 🏗 Step 1: Provision AWS Infrastructure

The script `aws-infra-setup.sh` provisions:

* VPC
* Subnets
* Security Groups
* 1 Control Plane EC2 instance
* 1 Worker Node EC2 instance

If you need additional worker nodes, edit:

```
aws-infra-setup.sh
```

---

### 🔑 Configure AWS Credentials

Before running the script, ensure AWS CLI is configured:

```bash
aws configure
```

Provide:

* AWS Access Key
* Secret Key
* Region
* Output format

---

### 🛠 Run Infrastructure Provision Script

⚠️ Before running, verify the EC2 key pair name inside `aws-infra-setup.sh` is correct.

Then execute:

```bash
sh aws-infra-setup.sh
```

After provisioning, the script will print:

* Control Plane public IP
* Worker Node public IP

Use these IPs to SSH into the instances.

---

## 🖥 Step 2: Configure Hostnames

Login to each node and set hostnames accordingly.

### On Control Plane

```bash
sudo hostnamectl set-hostname controlplane
exec bash
```

### On Worker Node

```bash
sudo hostnamectl set-hostname node01
exec bash
```

---

## ⚙️ Step 3: Install Common Dependencies

On **both nodes**, run:

```bash
sudo su
sh common.sh
```

This script installs:

* container runtime
* kubeadm
* kubelet
* kubectl
* Required system configurations

---

## 🧩 Step 4: Configure kubeadm

On the **control plane node**, edit:

```
kubeadm.config
```

Retrieve private IP of control plane:

```bash
hostname -I
```

Update these fields inside `kubeadm.config`:

```yaml
advertiseAddress: "10.0.1.205"
controlPlaneEndpoint: "10.0.1.205:6443"
```

Replace with your actual private IP.

---

## 🚀 Step 5: Initialize Control Plane

Run on control plane:

```bash
sudo kubeadm init --config=kubeadm.config
```

After successful initialization, configure kubectl:

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

---

## 🧰 Step 6: Add kubectl Shortcuts (Optional)

Edit:

```bash
vim ~/.bashrc
```

Add:

```bash
alias k='kubectl'
source <(kubectl completion bash)
complete -F __start_kubectl k
```

Reload:

```bash
source ~/.bashrc
```

Verify:

```bash
k get nodes
```

---

## 🔗 Step 7: Join Worker Node

On control plane, generate join command:

```bash
sudo kubeadm token create --print-join-command
```

Copy the output and execute it on **node01**.

After joining, check:

```bash
k get nodes
```

You may see:

```
NAME           STATUS     ROLES           AGE     VERSION
controlplane   NotReady   control-plane   6m23s   v1.33.0
node01         NotReady   <none>          22s     v1.33.0
```

Nodes are `NotReady` because no CNI plugin is installed yet.

---

## 🌐 Step 8: Install Calico CNI

On control plane:

```bash
curl -L https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml -o calico.yaml
```

```bash
kubectl apply -f calico.yaml
```

Wait a few minutes, then verify:

```bash
k get nodes
```

Now both nodes should be in:

```
Ready
```

---

## 🧹 Cleanup (Avoid AWS Costs)

After completing your practice, destroy infrastructure:

```bash
sh aws-infra-down.sh
```

This removes:

* EC2 instances
* VPC
* Associated resources

Always clean up to avoid unnecessary AWS charges.

---