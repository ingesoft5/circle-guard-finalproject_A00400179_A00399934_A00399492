# Análisis de costos de infraestructura

**Documento:** HU-17 (Sprint 2 · E2.9, criterio 9)
**Última actualización:** 2026-11-16
**Moneda:** USD · **Región:** `us-east-2` · **Presupuesto absoluto:** 15 USD
**Estado:** estimación basada en la AWS Pricing API y en las sesiones ejecutadas de HU-01. La
factura real se consulta en Billing; la captura de cierre está pendiente (§5).

> Los precios son de referencia (Pricing API del 2026-11-02) y pueden cambiar. No incluyen
> impuestos. Los créditos del plan gratuito **no** se cuentan como presupuesto disponible.

## 1. Resumen ejecutivo

| Concepto | Valor |
|---|---|
| Presupuesto del proyecto | 15.00 USD |
| Gasto estimado acumulado (HU-01 a HU-07) | ≈ 3.00 USD |
| Sesión típica de 4 h con `ci` + `nexus` | ≈ 0.81 USD |
| Costo de mantener todo encendido 24/7 | ≈ 4.98 USD/día · ≈ 151.5 USD/mes |
| Costo objetivo del Sprint 2 | ≤ 4.00 USD adicionales |
| Saldo estimado al cierre | ≥ 8.00 USD |

La conclusión es simple: **el proyecto es viable solo si los ambientes se apagan**. El EBS es el
costo dominante cuando todo está detenido; las horas de cómputo son el costo dominante cuando está
encendido.

## 2. Tarifas de referencia

| Recurso | Tarifa | Fuente |
|---|---|---|
| EC2 `m7i-flex.large` (2 vCPU, 8 GiB) | 0.09576 USD/h | Pricing API |
| EC2 `t3.small` (2 vCPU, 2 GiB) | ≈ 0.0208 USD/h | Pricing API |
| IPv4 pública | 0.005 USD/h por IP | Pricing API |
| EBS gp3 cifrado | 0.08 USD/GB-mes | Pricing API |
| Transferencia de salida | 0.09 USD/GB | Pricing API |
| SSM Parameter Store estándar | 0.00 | Capa gratuita |
| KMS `aws/ssm` | 0.00 | Capa gratuita |
| VPC, subredes, IGW, security groups, IAM | 0.00 | Sin cargo |
| NAT Gateway / ELB / Elastic IP | **no se usan** | 0.00 |

## 3. Costo del estado actual (Sprint 1, Compose sobre EC2)

### 3.1 Topología

| Componente | Tipo | Cantidad | Estado habitual |
|---|---|---|---|
| `ci` (Jenkins + SonarQube + dind) | `m7i-flex.large` | 1 | Detenida |
| `nexus` (registro CNCF Distribution) | `m7i-flex.large` | 1 | Detenida |
| `env-dev`, `env-stage`, `env-prod` | `t3.small` | 3 | Detenidas o no creadas |
| EBS | gp3 | 55 GiB | Siempre facturado |

### 3.2 Costo por escenario

| Escenario | Cómputo | EBS/día | Total |
|---|---|---|---|
| Todo detenido | 0.00 USD/h | 0.145 | 0.145 USD/día |
| `ci` + `nexus` encendidas | 0.1915 USD/h + IPv4 0.010 | 0.145 | ≈ 0.2015 USD/h + EBS |
| Sesión de 4 h | ≈ 0.81 USD | 0.024 | ≈ 0.83 USD |
| Todo encendido 24/7 | 0.2075 USD/h | 0.145 | ≈ 4.98 USD/día · 151.5 USD/mes |

**Lectura:** encendido 24/7, el presupuesto de 15 USD se agota en ~3 días. Por eso HU-01 impuso
apagado automático a las 4 h y trabajo por sesiones.

### 3.3 Gasto real registrado

| Fecha | Sesión | Duración | Costo estimado | Fuente |
|---|---|---|---|---|
| 2026-11-02 | Creación de `ci` y `nexus`, Jenkins/Sonar/Nexus | ≈ 35 min | ≈ 0.13 USD | [`../evidencias/hu-01/14-despliegue-aws-fase4.md`](../evidencias/hu-01/14-despliegue-aws-fase4.md) |
| 2026-11-03/04 | Prueba de aislamiento con tráfico | 2 sesiones | ≈ 0.03 USD + EBS | [`../evidencias/hu-01/14-despliegue-aws-fase4.md`](../evidencias/hu-01/14-despliegue-aws-fase4.md) |
| 2026-11-05/08 | Builds de HU-06/HU-07 | varias | no consolidado en el repositorio | Jenkins + Billing |
| Acumulado declarado | — | — | **≈ 3.00 USD** | [`../../README.md`](../../README.md) |

El EBS de 55 GiB se cobra desde que existe: **≈ 0.145 USD/día ≈ 4.40 USD/mes**. Si los volúmenes
se conservan dos meses, el EBS solo consume ≈ 8.80 USD.

## 4. Costo objetivo del Sprint 2 (Terraform + Kubernetes + observabilidad)

### 4.1 Supuestos

- Un clúster k3s de **un nodo** `m7i-flex.large` (8 GiB) que reemplaza a los tres `t3.small` para
  dev/stage, y un segundo nodo solo para prod durante la demo.
- Observabilidad en el mismo nodo (Prometheus, Grafana, Jaeger, Loki) con límites de memoria; sin
  nodo dedicado.
- Ingress en el propio nodo (sin ELB, que costaría ≈ 0.0225 USD/h adicionales).
- EBS adicional para el nodo: 30 GiB (≈ 0.0033 USD/h).
- Sesiones de 4 h, apagado automático.

### 4.2 Estimación por sesión

| Recurso | Tarifa/h | Horas | Costo |
|---|---:|---:|---:|
| Nodo k3s `m7i-flex.large` | 0.09576 | 4 | 0.383 |
| IPv4 pública | 0.00500 | 4 | 0.020 |
| EBS 30 GiB | 0.00329 | 4 | 0.013 |
| Segundo nodo prod (solo demo) | 0.09576 | 2 | 0.192 |
| Transferencia (reserva 1 GB) | 0.09/GB | — | 0.090 |
| **Total por sesión con demo** | | | **≈ 0.70 USD** |
| **Total por sesión sin demo** | | | **≈ 0.42 USD** |

### 4.3 Estimación del Sprint 2

| Actividad | Sesiones | Costo estimado |
|---|---:|---:|
| Desarrollo de Terraform (plan, sin apply) | 3 | 0.00 (plan no crea recursos) |
| Apply de dev + validación | 1 | 0.42 |
| Apply de stage + validación | 1 | 0.42 |
| Apply de prod + demo de rollback | 1 | 0.70 |
| Ensayo de la sustentación | 1 | 0.70 |
| Contingencia (reintentos, 2 sesiones) | 2 | 0.84 |
| EBS de 30 GiB durante 30 días | — | 2.40 |
| **Total estimado Sprint 2** | **8** | **≈ 5.48 USD** |

Con el acumulado de ≈ 3.00 USD, el total quedaría en **≈ 8.5 USD**, por debajo del presupuesto de
15 USD y de la línea operativa de 12 USD. Si se conservan los volúmenes más de 60 días, el EBS
puede empujar el total por encima de 12 USD: **destruir al cerrar la evaluación**.

> Ajuste si se usa EKS en lugar de k3s: EKS cobra ≈ 0.10 USD/h por clúster, más los nodos. Una
> sesión de 4 h sube ≈ 0.40 USD. Sigue siendo viable, pero reduce el margen. La decisión k3s/EKS
> pertenece a HU-09/HU-10.

## 5. Cómo obtener el costo real (pendiente de captura)

### 5.1 Consola de AWS

1. Billing and Cost Management → **Bills** → mes en curso.
2. Filtrar por `us-east-2` y por etiqueta `Project=circleguard`.
3. Captura sin datos de tarjeta ni correo: `docs/evidencias/hu-17/costos-billing.png`.
4. Cost Explorer → **Cost by service** → captura del acumulado.

### 5.2 CLI (solo lectura)

```bash
aws ce get-cost-and-usage \
  --time-period Start=2026-11-01,End=2026-11-30 \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --region us-east-1
```

**Salida esperada:** JSON con el costo por servicio. Guardar como
`docs/evidencias/hu-17/costos-cli.json` (sin credenciales).

### 5.3 Estimación local del proyecto

```bash
bash infra/bootstrap-servers.sh --plan   # no crea nada; imprime el costo estimado
bash infra/teardown.sh --status          # estado de instancias y volúmenes
```

El registro local vive en `~/.circleguard/budget/ledger.tsv`. **No es la factura**: AWS factura con
retraso y el registro solo ve lo que hacen los scripts.

## 6. Prácticas de FinOps aplicadas

| Práctica | Implementación | Ahorro |
|---|---|---|
| Apagado automático | `AUTO_STOP_HOURS=4` en cada instancia | Evita sesiones olvidadas de 24 h |
| Sin NAT Gateway | Salida por IGW y IP pública | ≈ 0.045 USD/h |
| Sin balanceadores | Ingress en el nodo / túnel SSH | ≈ 0.0225 USD/h por ELB |
| Sin Elastic IP | IP pública automática que se libera al detener | ≈ 0.005 USD/h |
| EBS mínimo | 30 + 25 GiB, sin snapshots | ≈ 4.40 USD/mes |
| Observabilidad en el mismo nodo | Límites de memoria, retención 7 días | Evita un nodo dedicado |
| Plan antes de apply | `terraform plan` revisado | Evita recursos huérfanos |
| Destruir al cerrar | `teardown.sh` / `terraform destroy` | Evita EBS indefinido |

## 7. Riesgos de costo

| Riesgo | Probabilidad | Impacto | Mitigación |
|---|---|---|---|
| Olvidar apagar el clúster | Media | Alto (≈ 2.30 USD/día) | Temporizador + verificación en el checklist |
| EKS cobrado por hora | Media | Medio | k3s si no se necesita EKS; apagar |
| Volúmenes huérfanos | Alta | Medio (0.145 USD/día) | `teardown.sh` + revisión de Billing |
| Transferencia por descargas grandes | Baja | Bajo | Usar el registro interno y túnel |
| Snapshots automáticos | Baja | Medio | Revisar políticas; no crear snapshots sin necesidad |

## 8. Evidencias para la rúbrica (C10)

| Evidencia | Archivo | Estado |
|---|---|---|
| Tabla de tarifas y estimación | este documento | Listo |
| Gasto real de una sesión | `14-despliegue-aws-fase4.md` | Listo |
| Captura de Billing del mes | `docs/evidencias/hu-17/costos-billing.png` | Pendiente |
| Salida de Cost Explorer | `docs/evidencias/hu-17/costos-cli.json` | Pendiente |
| Estimación del Sprint 2 | §4.3 | Listo (estimación) |
| Registro de apagado | `teardown.sh --status` | Verificar al cierre |

**Criterio de cierre:** la rúbrica pide “estimación y costos reales disponibles”. La estimación está
completa; la captura de Billing es el único faltante y se toma el día de la sustentación.
