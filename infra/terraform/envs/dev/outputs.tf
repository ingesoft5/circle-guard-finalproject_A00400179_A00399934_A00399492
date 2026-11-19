output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_id" {
  value = module.network.public_subnet_id
}

output "node_public_ip" {
  value = module.compute.public_ip
}

output "kubeconfig_parameter" {
  value = module.compute.kubeconfig_parameter
}
