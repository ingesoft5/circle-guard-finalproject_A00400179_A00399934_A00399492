environment        = "tools"
vpc_cidr           = "10.40.0.0/16"
public_subnet_cidr = "10.40.1.0/24"
instance_type      = "m7i-flex.large"
volume_size        = 60
terraform_version  = "1.17.2"

repositories = [
  "circleguard-auth-service",
  "circleguard-dashboard-service",
  "circleguard-file-service",
  "circleguard-form-service",
  "circleguard-gateway-service",
  "circleguard-identity-service",
  "circleguard-notification-service",
  "circleguard-promotion-service",
  "circleguard-web",
]
