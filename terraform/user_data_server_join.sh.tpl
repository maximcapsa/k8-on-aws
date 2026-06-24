#!/bin/bash
set -euxo pipefail

# --- swap to relieve memory pressure on the 1 GiB t2.micro ---
if [ ! -f /swapfile ]; then
  dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

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

# Join the etcd cluster as another server. k3s retries until the init server's
# API is reachable, so ordering during boot doesn't matter.
curl -sfL https://get.k3s.io | K3S_TOKEN="${token}" INSTALL_K3S_EXEC="server \
  --server https://${server_ip}:6443 \
  --disable traefik --disable servicelb --disable metrics-server \
  --node-ip $PRIVATE_IP --tls-san $PUBLIC_IP \
  --kubelet-arg=image-credential-provider-config=/etc/kubernetes/image-credential-provider/config.yaml \
  --kubelet-arg=image-credential-provider-bin-dir=/etc/kubernetes/image-credential-provider \
  --write-kubeconfig-mode 644" sh -

echo "server-join bootstrap complete"
