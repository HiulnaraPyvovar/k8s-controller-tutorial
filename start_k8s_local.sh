#!/bin/bash

# Exit on error
set -e

echo "Starting Kubernetes cluster setup..."

# Detect and set the system architecture
ARCH=$(uname -m | sed -e 's/^x86_64$/amd64/' -e 's/^aarch64$/arm64/')
echo "Detected architecture: ${ARCH}"

# Function to check if a process is running
is_running() {
    pgrep -f "$1" >/dev/null
}

# Function to kill process if running
stop_process() {
    if is_running "$1"; then
        echo "Stopping $1..."
        sudo pkill -f "$1" || true
        while is_running "$1"; do
            sleep 1
        done
    fi
}

cleanup() {
    echo "Stopping Kubernetes components before cleanup..."
    stop_process "kube-controller-manager"
    stop_process "kubelet"
    stop_process "kube-scheduler"
    stop_process "kube-apiserver"
    stop_process "containerd"
    stop_process "etcd"
    echo "All components stopped."

    echo "Cleaning up directories and files..."
    sudo rm -rf ./etcd
    sudo rm -rf ./kubebuilder
    sudo rm -rf /opt/cni
    sudo rm -rf /etc/cni/net.d
    sudo rm -rf /var/lib/kubelet/*
    sudo rm -rf /run/containerd/*
    sudo rm -rf /etc/containerd/config.toml
    sudo rm -rf /var/lib/containerd
    sudo rm -rf /etc/kubernetes/manifests
    sudo rm -rf /var/log/kubernetes
    sudo rm -f /tmp/sa.key /tmp/sa.pub /tmp/token.csv /tmp/ca.key /tmp/ca.crt

    # Optionally clean kubectl config (be careful if you use it for other clusters)
    # If you remove this, ensure you manually delete the test-context
    if sudo kubebuilder/bin/kubectl config current-context | grep -q "test-context"; then
        echo "Removing test-context from kubectl config..."
        sudo kubebuilder/bin/kubectl config unset users.test-user || true
        sudo kubebuilder/bin/kubectl config unset clusters.test-env || true
        sudo kubebuilder/bin/kubectl config unset contexts.test-context || true
    fi

    echo "Cleanup complete."
}

# --- Main Setup and Start Process ---

# 1. Prepare Directories
echo "Creating necessary directories..."
sudo mkdir -p ./kubebuilder/bin
sudo mkdir -p /etc/cni/net.d
sudo mkdir -p /var/lib/kubelet
sudo mkdir -p /etc/kubernetes/manifests
sudo mkdir -p /var/log/kubernetes
sudo mkdir -p /etc/containerd/
sudo mkdir -p /run/containerd
sudo mkdir -p /var/lib/containerd
sudo chmod 711 /var/lib/containerd # Ensure containerd data directory has correct permissions
sudo mkdir -p /var/lib/kubelet/pki # For kubelet certs
sudo mkdir -p /var/lib/kubelet/pods # Kubelet pod working directory
sudo chmod 750 /var/lib/kubelet/pods
sudo mkdir -p /var/lib/kubelet/plugins # Kubelet plugins directory
sudo chmod 750 /var/lib/kubelet/plugins
sudo mkdir -p /var/lib/kubelet/plugins_registry # Kubelet plugins registry
sudo chmod 750 /var/lib/kubelet/plugins_registry

# 2. Download Kubernetes Components (kubebuilder-tools, kubelet, controller-manager, scheduler)
echo "Downloading kubebuilder tools (etcd, kubectl, etc.)..."
curl -L "https://storage.googleapis.com/kubebuilder-tools/kubebuilder-tools-1.30.0-linux-${ARCH}.tar.gz" -o /tmp/kubebuilder-tools.tar.gz
sudo tar -C ./kubebuilder --strip-components=1 -zxf /tmp/kubebuilder-tools.tar.gz
rm /tmp/kubebuilder-tools.tar.gz
sudo chmod -R 755 ./kubebuilder/bin

echo "Downloading kubelet..."
sudo curl -L "https://dl.k8s.io/v1.30.0/bin/linux/${ARCH}/kubelet" -o kubebuilder/bin/kubelet
sudo chmod 755 kubebuilder/bin/kubelet

echo "Downloading kube-controller-manager and kube-scheduler..."
sudo curl -L "https://dl.k8s.io/v1.30.0/bin/linux/${ARCH}/kube-controller-manager" -o kubebuilder/bin/kube-controller-manager
sudo curl -L "https://dl.k8s.io/v1.30.0/bin/linux/${ARCH}/kube-scheduler" -o kubebuilder/bin/kube-scheduler
sudo chmod 755 kubebuilder/bin/kube-controller-manager
sudo chmod 755 kubebuilder/bin/kube-scheduler

# 3. Generate Certificates and Tokens
echo "Generating service account key pair..."
openssl genrsa -out /tmp/sa.key 2048
openssl rsa -in /tmp/sa.key -pubout -out /tmp/sa.pub

echo "Generating token file..."
TOKEN="1234567890"
echo "${TOKEN},admin,admin,system:masters" > /tmp/token.csv

echo "Generating CA certificate for kubelet..."
openssl genrsa -out /tmp/ca.key 2048
openssl req -x509 -new -nodes -key /tmp/ca.key -subj "/CN=kubelet-ca" -days 365 -out /tmp/ca.crt
sudo cp /tmp/ca.crt /var/lib/kubelet/ca.crt
sudo cp /tmp/ca.crt /var/lib/kubelet/pki/ca.crt

echo "Generating self-signed kubelet serving certificate..."
sudo openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout /var/lib/kubelet/pki/kubelet.key \
    -out /var/lib/kubelet/pki/kubelet.crt \
    -days 365 \
    -subj "/CN=$(hostname)"
sudo chmod 600 /var/lib/kubelet/pki/kubelet.key
sudo chmod 644 /var/lib/kubelet/pki/kubelet.crt

# 4. Set up Kubeconfig
echo "Setting up kubectl kubeconfig..."
sudo kubebuilder/bin/kubectl config set-credentials test-user --token=1234567890
sudo kubebuilder/bin/kubectl config set-cluster test-env --server=https://127.0.0.1:6443 --insecure-skip-tls-verify
sudo kubebuilder/bin/kubectl config set-context test-context --cluster=test-env --user=test-user --namespace=default
sudo kubebuilder/bin/kubectl config use-context test-context

# 5. Download and Configure Containerd & CNI
echo "Installing containerd and CNI plugins..."
sudo mkdir -p /opt/cni/bin # CNI bin dir
sudo mkdir -p /opt/cni/lib # containerd needs this for binaries too, if extracted there

# Download and extract containerd
wget "https://github.com/containerd/containerd/releases/download/v2.0.5/containerd-static-2.0.5-linux-${ARCH}.tar.gz" -O /tmp/containerd.tar.gz
sudo tar zxf /tmp/containerd.tar.gz -C /opt/cni/ # Extract into /opt/cni/
rm /tmp/containerd.tar.gz

# Download runc
sudo curl -L "https://github.com/opencontainers/runc/releases/download/v1.2.6/runc.${ARCH}" -o /opt/cni/bin/runc

# Download and extract CNI plugins
wget "https://github.com/containernetworking/plugins/releases/download/v1.6.2/cni-plugins-linux-${ARCH}-v1.6.2.tgz" -O /tmp/cni-plugins.tgz
sudo tar zxf /tmp/cni-plugins.tgz -C /opt/cni/bin/ # Extract into /opt/cni/bin/
rm /tmp/cni-plugins.tgz

# Set permissions for all CNI components
sudo chmod -R 755 /opt/cni

# Configure CNI
echo "Configuring CNI network..."
cat <<EOF | sudo tee /etc/cni/net.d/10-mynet.conf
{
    "cniVersion": "0.3.1",
    "name": "mynet",
    "type": "bridge",
    "bridge": "cni0",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "subnet": "10.22.0.0/16",
        "routes": [
            { "dst": "0.0.0.0/0" }
        ]
    }
}
EOF

# Configure containerd
echo "Configuring containerd..."
cat <<EOF | sudo tee /etc/containerd/config.toml
version = 3

[grpc]
  address = "/run/containerd/containerd.sock"

[plugins.'io.containerd.cri.v1.runtime']
  enable_selinux = false
  enable_unprivileged_ports = true
  enable_unprivileged_icmp = true
  device_ownership_from_security_context = false

[plugins.'io.containerd.cri.v1.images']
  snapshotter = "native"
  disable_snapshot_annotations = true

[plugins.'io.containerd.cri.v1.runtime'.cni]
  bin_dir = "/opt/cni/bin"
  conf_dir = "/etc/cni/net.d"

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc]
  runtime_type = "io.containerd.runc.v2"

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]
  SystemdCgroup = false
EOF

# Configure kubelet
echo "Configuring kubelet..."
cat << EOF | sudo tee /var/lib/kubelet/config.yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
authentication:
  anonymous:
    enabled: true
  webhook:
    enabled: true
  x509:
    clientCAFile: "/var/lib/kubelet/ca.crt"
authorization:
  mode: AlwaysAllow
clusterDomain: "cluster.local"
clusterDNS:
  - "10.0.0.10"
resolvConf: "/etc/resolv.conf"
runtimeRequestTimeout: "15m"
failSwapOn: false
seccompDefault: true
serverTLSBootstrap: false
containerRuntimeEndpoint: "unix:///run/containerd/containerd.sock"
staticPodPath: "/etc/kubernetes/manifests"
EOF

# Ensure proper permissions for kubelet config files
sudo chmod 644 /var/lib/kubelet/ca.crt
sudo chmod 644 /var/lib/kubelet/config.yaml

# 6. Get Host IP
HOST_IP=$(hostname -I | awk '{print $1}')
echo "Host IP: $HOST_IP"

# 7. Start Core Components
echo "Starting etcd..."
sudo kubebuilder/bin/etcd \
    --advertise-client-urls http://$HOST_IP:2379 \
    --listen-client-urls http://0.0.0.0:2379 \
    --data-dir ./etcd \
    --listen-peer-urls http://0.0.0.0:2380 \
    --initial-cluster default=http://$HOST_IP:2380 \
    --initial-advertise-peer-urls http://$HOST_IP:2380 \
    --initial-cluster-state new \
    --initial-cluster-token test-token &

echo "Starting kube-apiserver..."
sudo kubebuilder/bin/kube-apiserver \
    --etcd-servers=http://$HOST_IP:2379 \
    --service-cluster-ip-range=10.0.0.0/24 \
    --bind-address=0.0.0.0 \
    --secure-port=6443 \
    --advertise-address=$HOST_IP \
    --authorization-mode=AlwaysAllow \
    --token-auth-file=/tmp/token.csv \
    --enable-priority-and-fairness=false \
    --allow-privileged=true \
    --profiling=false \
    --storage-backend=etcd3 \
    --storage-media-type=application/json \
    --v=0 \
    --service-account-issuer=https://kubernetes.default.svc.cluster.local \
    --service-account-key-file=/tmp/sa.pub \
    --service-account-signing-key-file=/tmp/sa.key &

echo "Starting containerd..."
# Using bash -c to ensure PATH is correctly set for sudo and backgrounding
sudo bash -c "export PATH=$PATH:/opt/cni/bin:/usr/sbin; /opt/cni/bin/containerd -c /etc/containerd/config.toml &"

echo "Starting kube-scheduler..."
sudo kubebuilder/bin/kube-scheduler \
    --kubeconfig=/root/.kube/config \
    --leader-elect=false \
    --v=2 \
    --bind-address=0.0.0.0 &

# Set up kubelet kubeconfig (copying root's kubeconfig for kubelet access)
sudo cp /root/.kube/config /var/lib/kubelet/kubeconfig
export KUBECONFIG=~/.kube/config # Ensure kubectl uses the correct config for the current user session

# Create service account and configmap (idempotent operations)
sudo kubebuilder/bin/kubectl create sa default 2>/dev/null || true
sudo kubebuilder/bin/kubectl create configmap kube-root-ca.crt --from-file=ca.crt=/tmp/ca.crt -n default 2>/dev/null || true

echo "Starting kubelet..."
# Using bash -c for kubelet due to complex PATH and backgrounding
sudo bash -c "export PATH=$PATH:/opt/cni/bin:/usr/sbin; kubebuilder/bin/kubelet \
    --kubeconfig=/var/lib/kubelet/kubeconfig \
    --config=/var/lib/kubelet/config.yaml \
    --root-dir=/var/lib/kubelet \
    --cert-dir=/var/lib/kubelet/pki \
    --tls-cert-file=/var/lib/kubelet/pki/kubelet.crt \
    --tls-private-key-file=/var/lib/kubelet/pki/kubelet.key \
    --hostname-override=$(hostname) \
    --pod-infra-container-image=registry.k8s.io/pause:3.10 \
    --node-ip=$HOST_IP \
    --cgroup-driver=cgroupfs \
    --max-pods=4 \
    --v=1 &"

# Label the node so static pods with nodeSelector can be scheduled (or just for general identification)
NODE_NAME=$(hostname)
echo "Labeling node ${NODE_NAME} as master..."
sudo kubebuilder/bin/kubectl label node "$NODE_NAME" node-role.kubernetes.io/master="" --overwrite || true

echo "Starting kube-controller-manager..."
sudo PATH=$PATH:/opt/cni/bin:/usr/sbin kubebuilder/bin/kube-controller-manager \
    --kubeconfig=/var/lib/kubelet/kubeconfig \
    --leader-elect=false \
    --service-cluster-ip-range=10.0.0.0/24 \
    --cluster-name=kubernetes \
    --root-ca-file=/var/lib/kubelet/ca.crt \
    --service-account-private-key-file=/tmp/sa.key \
    --use-service-account-credentials=true \
    --v=2 &

# --- Remove Taint (Explicitly added as per your request) ---
echo "Waiting for node to become Ready and then removing 'uninitialized' taint..."
# Wait for node to be ready first, this might take a moment
sudo kubebuilder/bin/kubectl wait --for=condition=Ready node/${NODE_NAME} --timeout=300s || { echo "Node did not become Ready in time."; exit 1; }

echo "Node ${NODE_NAME} is Ready. Removing uninitialized taint..."
# Remove the taint that prevents scheduling if cloud-provider=external was used or implied earlier
sudo kubebuilder/bin/kubectl taint nodes "$NODE_NAME" node.cloudprovider.kubernetes.io/uninitialized:NoSchedule- || true
echo "Taint removal attempted."

echo "Waiting for all components to stabilize..."
sleep 15

echo "Verifying Kubernetes cluster setup..."
sudo kubebuilder/bin/kubectl get nodes
sudo kubebuilder/bin/kubectl get all -A
sudo kubebuilder/bin/kubectl get componentstatuses || true # This command might show 'unknown' for some components in recent K8s versions, which is normal.
sudo kubebuilder/bin/kubectl get --raw='/readyz?verbose'

echo "Kubernetes cluster setup complete. Attempting to deploy test pod..."

# 8. Test the Setup (Deploy a test pod)
sudo kubebuilder/bin/kubectl apply -f -<<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-pod-2
spec:
  containers:
    - name: test-container-nginx
      image: nginx:1.21
      securityContext:
        privileged: true
EOF

echo "Waiting for test-pod-2 to become ready..."
sudo kubebuilder/bin/kubectl wait --for=condition=ready pod/test-pod-2 --timeout=300s || { echo "Test pod did not become Ready in time."; exit 1; }

echo "Test pod test-pod-2 is Ready. Accessing it..."
# Get the container ID dynamically
CONTAINER_ID=$(sudo /opt/cni/bin/ctr -n k8s.io c ls | grep test-pod-2 | awk '{print $1}')

if [ -z "$CONTAINER_ID" ]; then
    echo "Error: Could not find container ID for test-pod-2. Ensure the pod is running."
else
    echo "Accessing test-pod-2 with container ID: $CONTAINER_ID"
    echo "To exit the container shell, type 'exit'."
    sudo /opt/cni/bin/ctr -n k8s.io tasks exec -t --exec-id m "$CONTAINER_ID" sh
fi

echo "Script finished."