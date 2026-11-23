# Evidencias E2.1 · Terraform (HU-09 S2)

**Estado:** implementado y aplicado en `dev`, `stage`, `prod` y `tools` (PR #15, #16 y #18).
Estado remoto en S3 con lock en DynamoDB. Falta la salida de `terraform fmt -check`/`validate` y un
`destroy` documentado.

**Documento dueño:** [`../../arquitectura/terraform.md`](../../arquitectura/terraform.md)
**Código:** [`infra/terraform/`](../../../infra/terraform)

## Matriz de criterios

| # | Criterio | Evidencia | Estado |
|---|---|---|---|
| 1 | Backend remoto S3 con versionado y cifrado | `01-bootstrap-plan.log`, `02-bootstrap-apply.log` | Cumplido |
| 2 | Lock de estado con DynamoDB | `02-bootstrap-apply.log` (`circleguard-tflock`) | Cumplido |
| 3 | Módulo de red reutilizable | `03-dev-red-plan.log`, `04-dev-red-apply.log` | Cumplido |
| 4 | Módulo de cómputo con k3s y `kubeconfig` en SSM | `07-dev-compute-plan.log`, `08-dev-compute-apply.log` | Cumplido |
| 5 | Módulo de registro (ECR, 9 imágenes) | `05-tools-registry-plan.log`, `06-tools-registry-apply.log` | Cumplido |
| 6 | Módulo de almacenamiento (S3 de datos) | `11-dev-extras-plan.log`, `12-dev-extras-apply.log` | Cumplido |
| 7 | Módulo de observabilidad (CloudWatch) | `11-dev-extras-plan.log`, `12-dev-extras-apply.log` | Cumplido |
| 8 | Elastic IP y salida pública estable | `13-dev-eip-plan.log`, `14-dev-eip-apply.log` | Cumplido |
| 9 | Servidor Jenkins declarado en Terraform | `15-tools-ci-plan.log`, `16-tools-ci-apply.log` | Cumplido |
| 10 | Ambientes stage y prod parametrizados y aplicados | `17-stage-full-plan.log`, `18-stage-full-apply.log`, `19-prod-full-plan.log`, `20-prod-full-apply.log` | Cumplido |
| 11 | Acceso del CI a la API de Kubernetes (`ci_cidr`) | `21-dev-ci-access-apply.log`, `22-stage-ci-access-apply.log`, `23-prod-ci-access-apply.log` | Cumplido |
| 12 | `terraform fmt -check` y `validate` | — | **Pendiente de evidencia** |
| 13 | Diagrama de recursos | `arquitectura/terraform.md` §4 | Cumplido (2026-11-20) |

## Archivos

| Archivo | Contenido |
|---|---|
| [`01-bootstrap-plan.log`](01-bootstrap-plan.log) / [`02-bootstrap-apply.log`](02-bootstrap-apply.log) | S3 de estado + DynamoDB (5 recursos) |
| [`03-dev-red-plan.log`](03-dev-red-plan.log) / [`04-dev-red-apply.log`](04-dev-red-apply.log) | VPC, subred, IGW y rutas de dev (5 recursos) |
| [`05-tools-registry-plan.log`](05-tools-registry-plan.log) / [`06-tools-registry-apply.log`](06-tools-registry-apply.log) | ECR con 9 repositorios (18 recursos) |
| [`07-dev-compute-plan.log`](07-dev-compute-plan.log) / [`08-dev-compute-apply.log`](08-dev-compute-apply.log) | Nodo k3s, EIP, SSM y security group (12 recursos) |
| [`09-stage-plan.log`](09-stage-plan.log) / [`10-prod-plan.log`](10-prod-plan.log) | Plan inicial de stage y prod |
| [`11-dev-extras-plan.log`](11-dev-extras-plan.log) / [`12-dev-extras-apply.log`](12-dev-extras-apply.log) | Bucket S3 + log group + alarma de CPU (6 recursos) |
| [`13-dev-eip-plan.log`](13-dev-eip-plan.log) / [`14-dev-eip-apply.log`](14-dev-eip-apply.log) | Elastic IP de dev (3 recursos) |
| [`15-tools-ci-plan.log`](15-tools-ci-plan.log) / [`16-tools-ci-apply.log`](16-tools-ci-apply.log) | Servidor Jenkins de tools (16 recursos) |
| [`17-stage-full-plan.log`](17-stage-full-plan.log) / [`18-stage-full-apply.log`](18-stage-full-apply.log) | Stack completo de stage (25 recursos) |
| [`19-prod-full-plan.log`](19-prod-full-plan.log) / [`20-prod-full-apply.log`](20-prod-full-apply.log) | Stack completo de prod (25 recursos) |
| [`21-dev-ci-access-apply.log`](21-dev-ci-access-apply.log) | Regla de la API de Kubernetes para el CIDR del CI en dev |
| [`22-stage-ci-access-apply.log`](22-stage-ci-access-apply.log) | Regla de la API de Kubernetes para el CIDR del CI en stage |
| [`23-prod-ci-access-apply.log`](23-prod-ci-access-apply.log) | Regla de la API de Kubernetes para el CIDR del CI en prod |

## Cómo regenerar la evidencia

```bash
cd infra/terraform/envs/dev
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan  -var="admin_cidr=<CIDR>" -out=dev.tfplan
terraform apply dev.tfplan
```

Guardar la salida de cada comando en esta carpeta con el siguiente número correlativo. No incluir
números de cuenta, IPs públicas sin sanear ni rutas personales.
