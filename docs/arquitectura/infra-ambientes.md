# Diagrama de ambientes de CircleGuard (HU-01)

Infraestructura de la plataforma en AWS: servidores para Jenkins, SonarQube y Nexus, y tres
ambientes aislados (`dev`, `stage`, `prod`). Todo se aprovisiona con `infra/bootstrap-*.sh` y
Docker Compose (ver [infra/README.md](../../infra/README.md)).

```mermaid
flowchart TB
    ops["Operadores del equipo<br/>(ADMIN_CIDRS, /32)"]

    subgraph aws["AWS · us-east-2 (Ohio)"]
        ssm[("SSM Parameter Store · SecureString<br/>/circleguard/tools/*<br/>/circleguard/dev/* · /stage/* · /prod/*<br/>/circleguard/ssh/*")]

        subgraph vpc["VPC circleguard-vpc · 10.20.0.0/16 · us-east-2a · Internet Gateway (sin NAT Gateway)"]
            subgraph tools["Subred tools · 10.20.0.0/24"]
                jenkins["Jenkins LTS 2.580.2<br/>c7i-flex.large · :8080 solo en 127.0.0.1<br/>JCasC, sin asistente"]
                sonar["SonarQube 26.10 + PostgreSQL 16<br/>m7i-flex.large · :9000"]
                nexus["Nexus Repository 3.96.5<br/>m7i-flex.large · :8081 UI/API<br/>:8082 registro circleguard-docker"]
            end
            subgraph dev["Subred dev · 10.20.10.0/24"]
                envdev["env-dev · t3.small<br/>Docker + Compose<br/>/opt/circleguard/dev/.env"]
            end
            subgraph stage["Subred stage · 10.20.20.0/24"]
                envstage["env-stage · t3.small<br/>Docker + Compose<br/>/opt/circleguard/stage/.env"]
            end
            subgraph prod["Subred prod · 10.20.30.0/24"]
                envprod["env-prod · t3.small<br/>Docker + Compose<br/>/opt/circleguard/prod/.env"]
            end
        end
    end

    ops -- "SSH 22 · UIs solo por túnel SSH (infra/tunnel.sh)" --> tools
    ops -- "SSH 22" --> envdev & envstage & envprod
    ops -. "bootstrap: lee secretos<br/>y los envía por SSH" .-> ssm
    jenkins -- "9000" --> sonar
    jenkins -- "8081 · 8082" --> nexus
    jenkins -- "SSH 22" --> envdev & envstage & envprod
    envdev & envstage & envprod -- "8082 pull" --> nexus
    envdev x--x envstage
    envstage x--x envprod
    envdev x--x envprod
```

`x--x` = tráfico **bloqueado**: ningún grupo de seguridad permite comunicación entre ambientes.
Desde Internet solo se acepta SSH (22) desde `ADMIN_CIDRS`: las interfaces HTTP de las
herramientas no se exponen, y su administración pasa por un túnel SSH cifrado.

## Comunicación permitida

Grupos de seguridad de `infra/bootstrap-network.sh`. Todo lo que no figura aquí está denegado.

| Origen | Destino | Puerto | Propósito |
|---|---|---|---|
| `ADMIN_CIDRS` | todos los servidores | 22 | Aprovisionamiento por SSH, y túnel SSH hacia las UIs de jenkins (8080), sonarqube (9000) y nexus (8081) |
| Internet (incluido `ADMIN_CIDRS`) | 8080 · 9000 · 8081 · 8082 | — | **Denegado**: las UIs HTTP no se exponen |
| `sg-jenkins` | `sg-sonarqube` | 9000 | Análisis estático (lo usará E1.4) |
| `sg-jenkins` | `sg-nexus` | 8081 · 8082 | Publicación de artefactos e imágenes (E1.3/E1.4) |
| `sg-jenkins` | `sg-env-{dev,stage,prod}` | 22 | Despliegue (E1.5) |
| `sg-env-{dev,stage,prod}` | `sg-nexus` | 8082 | Descarga de imágenes |
| todos (salida) | 0.0.0.0/0 | 80 · 443 | Paquetes, imágenes y plugins |
| `sg-env-X` | `sg-env-Y` | — | **Denegado** (no existe regla de entrada ni de salida) |
| sonarqube · nexus | ambientes | — | **Denegado** |
| Internet | registro Docker de Nexus (8082) | — | **Denegado** |

## Aislamiento de los ambientes

| Dimensión | Mecanismo |
|---|---|
| Cómputo | Una instancia EC2 por ambiente |
| Red | Subred propia y grupo de seguridad propio, sin reglas hacia otros ambientes; salida limitada a 80/443 y al registro |
| Credenciales | Ruta SSM propia con valores **distintos** por ambiente. Cada host recibe solo el `.env` de su ambiente (`0600 root`) |
| Acceso | Par de llaves SSH propio por ambiente (`circleguard-dev`, `circleguard-stage`, `circleguard-prod`) y otro para herramientas |
| Datos | Volúmenes en el EBS cifrado de cada instancia |
| Identificación | Etiquetas `Project`, `Story`, `ManagedBy`, `Role` y `Environment` |

Comprobación: `bash infra/verify-infra.sh --isolation` intenta cada conexión desde los propios
hosts con `nc` y exige `closed` entre ambientes y `open` en los flujos permitidos.

## Servidores

| Host | Subred | Tipo | Disco | Contenido |
|---|---|---|---|---|
| circleguard-jenkins | tools | c7i-flex.large | 30 GiB gp3 cifrado | Jenkins (imagen derivada de la LTS con JCasC fijado) |
| circleguard-sonarqube | tools | m7i-flex.large | 30 GiB gp3 cifrado | SonarQube Community Build y PostgreSQL 16 (sin puerto publicado) |
| circleguard-nexus | tools | m7i-flex.large | 40 GiB gp3 cifrado | Nexus Repository CE y el repositorio Docker hosted `circleguard-docker` (etiquetas inmutables) |
| circleguard-env-{dev,stage,prod} | dev · stage · prod | t3.small | 20 GiB gp3 cifrado | Docker Engine y Compose, listo para E1.3/E1.5 |

Todas las instancias usan Ubuntu 24.04 LTS, IMDSv2 obligatorio, IPv4 pública automática (sin
Elastic IP) y no tienen rol IAM. Los `t3.small` usan créditos de CPU `standard`; los tipos flex no
usan créditos. La cuenta está en el plan gratuito de AWS, que solo lanza tipos aptos para la capa
gratuita.

## Identidades y autorización

Ninguna identidad tiene claves de acceso permanentes. Cada capacidad tiene su propia identidad, y
AWS, no los scripts, impide que una capacidad se use desde otra. Plantillas en
[`infra/config/iam/`](../../infra/config/iam/) y creación con `infra/bootstrap-iam.sh`.

```mermaid
flowchart LR
    persona(["Persona: contraseña y MFA<br/>solo en páginas de AWS"])
    subgraph estacion["Estación de trabajo (WSL, ~/.circleguard/aws 0700)"]
        login["aws login<br/>usuario circleguard-hu01-operator<br/>(sin claves)"]
        reader["Rol circleguard-hu01-reader<br/>describir, precios, detener"]
        operator["Rol circleguard-hu01-operator<br/>crear e iniciar, sin borrar<br/>sesión ≤ 1 h"]
        scripts["infra/*.sh"]
    end
    subgraph navegador["Navegador: consola de AWS"]
        cloudshell["AWS CloudShell<br/>usuario circleguard-hu01-teardown"]
        teardown["Rol circleguard-hu01-teardown<br/>borrar solo Project=circleguard"]
    end
    aws[("Recursos de HU-01<br/>us-east-2")]

    persona -->|"inicio de sesión"| login
    persona -->|"código MFA en la AWS CLI (unlock)"| operator
    persona -->|"inicio de sesión + MFA"| cloudshell
    login --> reader
    login --> operator
    reader --> scripts
    operator --> scripts
    scripts --> aws
    cloudshell -->|"código MFA, < 15 min"| teardown
    teardown --> aws
    login -- "denegado por IAM" --x teardown
```

| Identidad | Puede | Cómo se obtiene | Límite impuesto por AWS |
|---|---|---|---|
| Rol `circleguard-hu01-reader` | Describir, precios, Access Analyzer, detener instancias | Sesión `aws login` del operador | Solo el usuario operador |
| Rol `circleguard-hu01-operator` | Crear e iniciar recursos acotados; ningún borrado ni permiso IAM | Código MFA nuevo en `AssumeRole` | MFA en cada asunción; sesión ≤ 1 h |
| Rol `circleguard-hu01-teardown` | Describir (política de lectura adjunta) y borrar recursos con `Project=circleguard` | Usuario de teardown en CloudShell | Solo ese usuario, MFA de menos de 15 min; nunca en la estación |

El simulador de políticas IAM confirma que ninguna de estas identidades puede crear credenciales,
modificar permisos, pasar roles, cambiar la cuenta o asumir el rol de teardown
([evidencia 09](../evidencias/hu-01/09-aws-preparacion-cuenta-e-iam.txt)).
