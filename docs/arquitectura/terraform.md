# Terraform en CircleGuard — diseño y consolidación **[S2]**

**Documento:** HU-17 (Sprint 2 · E2.9) sobre el diseño de HU-09 (S2 · E2.1)
**Última actualización:** 2026-11-16
**Estado:** **Pendiente de implementación.** No hay archivos `.tf` en el repositorio. La
infraestructura actual se aprovisiona con Bash idempotente (`infra/bootstrap-*.sh`) y está
documentada en [`../operacion/infraestructura-aws.md`](../operacion/infraestructura-aws.md). Este
documento fija el contrato esperado y se completa cuando HU-09 (S2) se mergee.

> Si el código de HU-09 difiere, **prevalece el código** y se corrige este documento en el mismo PR.

## 1. Qué exige el criterio E2.1

| Criterio | Artefacto | Estado |
|---|---|---|
| Infraestructura declarada en Terraform, no solo Bash | `infra/terraform/` con módulos | Pendiente |
| Módulos reutilizables: red, cómputo/clúster, registro, almacenamiento, observabilidad | Un módulo por carpeta con `variables.tf`, `main.tf`, `outputs.tf` | Pendiente |
| Configuraciones independientes y parametrizables para dev, stage y prod | `environments/{dev,stage,prod}` | Pendiente |
| Cada ambiente configura recursos, tamaños, nombres y parámetros | `terraform.tfvars` por ambiente | Pendiente |
| Backend remoto (por ejemplo S3) | `backend "s3"` | Pendiente |
| Lock de estado (DynamoDB o compatible) | `dynamodb_table` / lock nativo | Pendiente |
| Sin credenciales en archivos ni en el repositorio | Variables sensibles + SSM/roles | Pendiente |
| `terraform fmt` y `terraform validate` correctos | Salida de ambos comandos | Pendiente |
| `terraform plan` antes de aplicar | Plan archivado como artefacto | Pendiente |
| Diagramas actualizados | Mermaid/draw.io de recursos y relaciones | Pendiente |

## 2. Estructura propuesta

```text
infra/terraform/
├── modules/
│   ├── network/          VPC, subredes, IGW, rutas, security groups
│   ├── compute/          clúster Kubernetes (k3s en EC2 o EKS) y nodos
│   ├── registry/         CNCF Distribution o ECR
│   ├── storage/          S3 para artefactos/estado y volúmenes
│   └── observability/    Prometheus, Grafana, Jaeger, Loki (Helm/recursos)
├── environments/
│   ├── dev/              main.tf · backend.tf · terraform.tfvars
│   ├── stage/
│   └── prod/
└── README.md
```

**Backend remoto.** Un bucket S3 por proyecto (`circleguard-tfstate-<cuenta>`) con versionado y
cifrado, y una tabla DynamoDB (`circleguard-tf-lock`) con `LockID`. El bucket y la tabla se crean
una vez con un `bootstrap` mínimo; no se versiona el estado.

**Aislamiento.** Un `workspace` o una carpeta por ambiente, con state separado. El nombre de los
recursos lleva el ambiente (`circleguard-dev-...`) para que el plan sea legible.

## 3. Contrato de variables

| Variable | dev | stage | prod | Notas |
|---|---|---|---|---|
| `aws_region` | `us-east-2` | `us-east-2` | `us-east-2` | Igual que HU-01 |
| `environment` | `dev` | `stage` | `prod` | Etiqueta obligatoria |
| `cluster_type` | `k3s` | `k3s` | `k3s` (o EKS) | Decisión de HU-09/HU-10 |
| `node_instance_type` | `m7i-flex.large` | `m7i-flex.large` | `m7i-flex.large` | 2 vCPU / 8 GiB |
| `node_count` | 1 | 1 | 2 | prod con 2 si el presupuesto lo permite |
| `registry_backend` | `distribution` | `distribution` | `distribution` | D-25 |
| `enable_observability` | `true` | `true` | `true` | Namespace `observability` |
| `auto_stop_hours` | 4 | 4 | 4 | Herencia de HU-01 |

Las credenciales **no** son variables de Terraform: se usan roles IAM y SSM. Si se necesita un
secreto, se referencia por ARN y se marca `sensitive = true`.

## 4. Flujo de aprovisionamiento

```bash
cd infra/terraform/environments/dev
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=dev.tfplan
# revisión humana del plan y aprobación de costo
terraform apply dev.tfplan
```

En Jenkins (HU-11) el flujo es `fmt` → `validate` → `plan` → aprobación → `apply`. Nunca
`apply` automático en prod. El plan se archiva como artefacto y se enlaza en el registro de cambios.

## 5. Dependencias con otras historias

| Necesidad | Historia | Efecto si falta |
|---|---|---|
| Decisión k3s vs EKS y tamaño de nodos | HU-09/HU-10 | El módulo `compute` no se puede cerrar |
| Imágenes y registro | HU-02/HU-06 | El clúster no tiene qué desplegar |
| Namespace y recursos de observabilidad | HU-13 | El módulo `observability` queda vacío |
| Certificados/TLS y RBAC | HU-14 | Ingress y métricas sin seguridad |
| Aprobación de costo | D-33 | No se puede aplicar en AWS |

## 6. Evidencias que debe producir HU-09 (para HU-17)

1. Árbol de módulos y `terraform.tfvars` de los tres ambientes (sin secretos).
2. Salida de `terraform fmt -check` y `terraform validate` (`Success`).
3. `terraform plan` de dev con el resumen de recursos (`Plan: N to add, 0 to change, 0 to destroy`).
4. `terraform apply` con la aprobación y el resultado.
5. Captura del bucket de estado con versionado y de la tabla de lock.
6. Diagrama de recursos y relaciones.
7. `terraform state list` (opcional, sin datos sensibles).
8. Registro del costo estimado del plan y del costo real posterior.

## 7. Riesgos conocidos

| Riesgo | Mitigación |
|---|---|
| Migrar de Bash a Terraform puede romper la infraestructura existente | Importar recursos o crear un ambiente nuevo; no destruir lo que ya funciona sin respaldo |
| El estado remoto contiene datos sensibles | Bucket privado, cifrado, versionado, acceso mínimo; nunca imprimir el state |
| `apply` accidental en prod | Aprobación manual + `plan` archivado + `prevent_destroy` donde aplique |
| Costo del clúster 24/7 | Apagado por horario; nodos pequeños; D-33 |
| Diferencias entre dev/stage/prod | Variables tipadas y validaciones (`validation` blocks) |
