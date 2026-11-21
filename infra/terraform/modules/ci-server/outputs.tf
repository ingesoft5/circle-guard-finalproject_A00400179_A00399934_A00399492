output "instance_id" {
  value = aws_instance.ci.id
}

output "public_ip" {
  value = aws_eip.ci.public_ip
}

output "jenkins_url" {
  value = "http://${aws_eip.ci.public_ip}:8080"
}
