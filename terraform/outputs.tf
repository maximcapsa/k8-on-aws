output "server_public_ips" {
  description = "Public IPs of all k3s server nodes"
  value       = concat([aws_instance.server_init.public_ip], aws_instance.server_join[*].public_ip)
}

output "app_urls" {
  description = "App is reachable on the NodePort of every node (Service load-balances across pods)"
  value = [
    for ip in concat([aws_instance.server_init.public_ip], aws_instance.server_join[*].public_ip) :
    "http://${ip}:${var.app_node_port}"
  ]
}

output "ecr_repository_url" {
  description = "ECR repository URL to push the app image to"
  value       = aws_ecr_repository.app.repository_url
}

output "github_actions_role_arn" {
  description = "Set this as the AWS_ROLE_ARN secret in the GitHub repo (used by the CI workflow)"
  value       = aws_iam_role.github_actions.arn
}

output "argocd_ui_hint" {
  description = "How to reach the Argo CD UI (run on any server node)"
  value       = "Connect to a server (EC2 Instance Connect), then: sudo k3s kubectl -n argocd port-forward svc/argocd-server 8080:443. Initial password: sudo k3s kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
