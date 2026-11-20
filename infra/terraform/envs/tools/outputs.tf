output "repository_urls" {
  value = module.registry.repository_urls
}

output "jenkins_url" {
  value = module.ci_server.jenkins_url
}

output "jenkins_public_ip" {
  value = module.ci_server.public_ip
}

output "jenkins_instance_id" {
  value = module.ci_server.instance_id
}
