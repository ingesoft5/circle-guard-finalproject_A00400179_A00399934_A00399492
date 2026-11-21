output "instance_id" {
  value = aws_instance.node.id
}

output "public_ip" {
  value = aws_eip.node.public_ip
}

output "security_group_id" {
  value = aws_security_group.node.id
}

output "kubeconfig_parameter" {
  value = "/circleguard/${var.environment}/kubeconfig"
}
