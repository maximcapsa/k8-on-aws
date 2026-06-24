# Kubernetes on AWS (k3s, HA)

A real, highly-available Kubernetes setup on AWS: **three `t2.micro` EC2
instances** running [k3s](https://k3s.io) as servers with **embedded-etcd HA**
(quorum of 3), plus **ArgoCD** for GitOps and **GitHub Actions** for CI. The
demo app is an nginx page backed by a **PersistentVolumeClaim**, run as a
StatefulSet replicated one-per-node with per-pod storage.

> Not free tier: three `t2.micro`s 24/7 exceed the 750h/mo allowance. This is
> intended to be **spun up for a demo and torn down** (`terraform destroy`).

## Architecture

```
GitHub push (app/**) ──▶ GitHub Actions ──(OIDC)──▶ build image ──▶ Amazon ECR
                              │
                              └─ commit new image tag to k8s/statefulset.yaml
                                                │
3× EC2 t2.micro — all k3s servers (etcd HA) ─────▼
  server-0 ──▶ ArgoCD ──(watches master, path k8s/)──▶ syncs StatefulSet/Service
  server-1 ┐  etcd quorum tolerates losing 1 node
  server-2 ┘                                      │
                                          NodePort :30080 on EVERY node
                                          (kube-proxy load-balances pods)  ◀── you
```

| Concern   | Choice                                          | Notes                 |
|-----------|-------------------------------------------------|-----------------------|
| Compute   | 3× `t2.micro`, public subnet, no NAT            | tear down when done   |
| Storage   | 30 GiB gp3 root + per-pod `local-path` PVC      | ≤30 GiB free          |
| Ingress   | NodePort `30080` on every node (no ELB)         | free                  |
| Registry  | Amazon ECR (private)                             | ≤500 MB free          |
| Cluster   | k3s embedded-etcd HA (3 servers) + ArgoCD       | —                     |

### ECR auth (the moving parts)
Unlike EKS, self-managed k3s doesn't resolve ECR credentials automatically, so:
- **CI → ECR push**: a GitHub OIDC provider + IAM role (Terraform) let the
  workflow assume a role — no static AWS keys. Put the role ARN
  (`terraform output github_actions_role_arn`) in the repo secret `AWS_ROLE_ARN`.
- **Nodes → ECR pull**: each node gets an IAM instance profile with ECR read
  plus the kubelet **ecr-credential-provider** plugin (installed in
  `user_data`), so the kubelet fetches short-lived ECR tokens via the node role.

### What this HA setup gives you
- ✅ **Control-plane HA** — 3 servers with embedded etcd; the cluster keeps
  working if one node dies (quorum 2/3).
- ✅ **App HA + load balancing** — 3 pods, one per node (topology spread), one
  Service load-balancing across them. Refresh shows different pod names
  (seeded into each pod's PVC).
- ❌ **Redundant external entry point** — each node exposes the NodePort, but
  there's no cross-node load balancer in front (that would need an ELB). For a
  demo, hit any node IP; if it dies, use another.

## Prerequisites

- AWS account + credentials configured locally (`aws configure`)
- Terraform ≥ 1.5
- Cluster access via **EC2 Instance Connect** (no key pair needed); leave
  `key_name = ""`
- If your account already has a GitHub Actions OIDC provider, set
  `create_github_oidc_provider = false` (only one per account is allowed).

## Deploy

1. **Provision** (creates the ECR repo, IAM/OIDC roles, and the cluster):
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   # optionally restrict admin_cidr to your IP
   terraform init
   terraform apply
   ```
   `server-0` initializes etcd + installs ArgoCD and applies the Argo
   `Application`; the other two servers join automatically. ~3–5 min.

2. **Wire up CI:** copy `terraform output github_actions_role_arn` into the
   GitHub repo secret **`AWS_ROLE_ARN`** (Settings → Secrets → Actions).

3. **Build the first image:** push a change under `app/`, or run the
   **Build & Deploy** workflow manually (Actions → Run workflow). It pushes to
   ECR and commits the image ref into `k8s/statefulset.yaml`; ArgoCD then syncs.
   (Until this runs, the app pods sit in ImagePullBackOff against the
   `REPLACE_WITH_ECR_IMAGE` placeholder — that's expected.)

4. **Open the app:** Terraform prints `app_urls` (one per node, e.g.
   `http://<ip>:30080`). The page shows the node hostname and the PVC-backed
   file naming the pod that served it.

## Accessing the cluster / ArgoCD

Connect to any **server** node with EC2 Instance Connect, then:
```bash
sudo k3s kubectl get nodes -o wide      # should show 3 Ready control-plane nodes
sudo k3s kubectl -n myapp get pods -o wide

# ArgoCD UI via tunnel:
sudo k3s kubectl -n argocd port-forward svc/argocd-server 8080:443
sudo k3s kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

## Tear down (do this when finished — it's billable)

```bash
cd terraform && terraform destroy
```

## Notes / known tight spots

- A 1 GiB `t2.micro` is **tight** for etcd + control plane + ArgoCD; bootstrap
  adds 2 GiB swap. If pods get OOM-killed, bump `instance_type` to `t3.small`.
- `local-path` PVCs are node-local and RWO, hence the StatefulSet with per-pod
  `volumeClaimTemplates` (each pod's data is independent).
- `server_count` controls cluster size — use an odd number (1 or 3) for a
  healthy etcd quorum.
