#!/bin/bash
set -euxo pipefail

# --- swap: etcd + control plane + ArgoCD are tight on a 1 GiB t2.micro ---
if [ ! -f /swapfile ]; then
  dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# --- discover our own IPs from IMDSv2 ---
IMDS_TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
  http://169.254.169.254/latest/meta-data/public-ipv4)
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
  http://169.254.169.254/latest/meta-data/local-ipv4)

# --- ECR credential provider so the kubelet can pull from private ECR ---
mkdir -p /etc/kubernetes/image-credential-provider
curl -sfL -o /etc/kubernetes/image-credential-provider/ecr-credential-provider \
  "https://github.com/kubernetes/cloud-provider-aws/releases/download/${ecr_cp_version}/ecr-credential-provider-linux-amd64"
chmod 0755 /etc/kubernetes/image-credential-provider/ecr-credential-provider
cat > /etc/kubernetes/image-credential-provider/config.yaml <<'EOF'
apiVersion: kubelet.config.k8s.io/v1
kind: CredentialProviderConfig
providers:
  - name: ecr-credential-provider
    matchImages:
      - "*.dkr.ecr.*.amazonaws.com"
      - "*.dkr.ecr.*.amazonaws.com.cn"
    defaultCacheDuration: "12h"
    apiVersion: credentialprovider.kubelet.k8s.io/v1
EOF

# --- init the embedded-etcd HA cluster (lean; fixed token for peers) ---
curl -sfL https://get.k3s.io | K3S_TOKEN="${token}" INSTALL_K3S_EXEC="server \
  --cluster-init \
  --disable traefik --disable servicelb --disable metrics-server \
  --node-ip $PRIVATE_IP --tls-san $PUBLIC_IP \
  --kubelet-arg=image-credential-provider-config=/etc/kubernetes/image-credential-provider/config.yaml \
  --kubelet-arg=image-credential-provider-bin-dir=/etc/kubernetes/image-credential-provider \
  --write-kubeconfig-mode 644" sh -

# wait for this node to be Ready
until /usr/local/bin/k3s kubectl get nodes 2>/dev/null | grep -q ' Ready'; do
  echo "waiting for k3s server..."
  sleep 5
done

# --- install Argo CD (cluster state is shared via etcd across all servers) ---
/usr/local/bin/k3s kubectl create namespace argocd
/usr/local/bin/k3s kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

until /usr/local/bin/k3s kubectl get crd applications.argoproj.io >/dev/null 2>&1; do
  echo "waiting for argocd CRDs..."
  sleep 5
done

# --- bootstrap the app via GitOps (Argo then syncs everything under k8s/) ---
/usr/local/bin/k3s kubectl apply -f ${argo_app_url}

echo "server-init bootstrap complete"
