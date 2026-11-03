# 16 · EULA de Nexus Repository Community Edition: información para la decisión del equipo

**Estado:** el EULA **no está aceptado** (`NEXUS_ACCEPT_EULA=false`). Nexus está desplegado en
`circleguard-nexus`, en línea y con la contraseña del administrador gestionada (evidencia 14). La
decisión corresponde al equipo; este documento no la toma.

Fuentes consultadas el 2026-11-02:
- EULA: <https://www.sonatype.com/dnt/usage/community-edition-eula> (la página no indica versión ni
  fecha de publicación).
- Incorporación a Community Edition: <https://help.sonatype.com/en/ce-onboarding.html>.
- Notas de la versión 3.87.0: <https://help.sonatype.com/en/sonatype-nexus-repository-3-87-0-release-notes.html>.

## 1. Texto y condiciones (citas del EULA y de la documentación oficial)

**EULA:**
- Licencia «non-transferable, non-assignable, non-sublicensable, non-exclusive, limited», para uso
  «solely for Licensee's internal business purposes».
- Prohíbe usar el producto «as a service bureau, ASP, or hosting service», hacer
  «reverse engineer, decompile, disassemble», «embed the Product or any Reports into any Licensee
  product or service offering», usarlo «for any benchmarking or competitive purposes» y
  «perform penetration testing, vulnerability testing or other security testing on the Product».
- El producto «contains a feature that sends Usage Information to Sonatype» (información técnica,
  estadística, de métricas y de rendimiento, que puede identificar al licenciatario, por ejemplo por
  su IP), y no se permite restringir esa telemetría.
- Se entrega «AS-IS, WITH ALL FAULTS», sin soporte («Sonatype will not provide any support and/or
  maintenance»), con una responsabilidad máxima de 1 000 USD.
- Sonatype puede terminarlo por incumplimiento; se rige por las leyes de Maryland. Sonatype puede
  modificar los términos, y seguir usando el producto equivale a aceptarlos.
- El texto no menciona precio, límites de uso, ni uso educativo o comercial de forma expresa.

**Documentación de Community Edition:**
- Hay que aceptar el EULA «either via the user interface within the wizard or through the EULA API»
  antes de que los usuarios puedan descargar o subir componentes.
- Límites: «up to 40,000 total components and 100,000 requests per day». Si se superan, «built-in
  safeguards will pause the addition of new components until usage returns below both thresholds».
- Se presenta como gratuita para «individual developers and small teams».

## 2. Interpretación técnica (no es asesoramiento legal)

- Mientras no se acepte, Nexus funciona, pero **no sirve componentes**: no se pueden descargar ni
  subir imágenes. Por eso el bootstrap no crea `circleguard-docker` ni configura el realm DockerToken
  ni el acceso anónimo.
- Aceptarlo cambiaría la configuración con estos pasos: `NEXUS_ACCEPT_EULA=true` en
  `infra/config/aws.env` (con su commit), arrancar `circleguard-nexus` y ejecutar
  `bash infra/bootstrap-nexus.sh --apply`. `configure.sh` lo acepta por la API REST y después crea el
  repositorio, el realm y el acceso anónimo deshabilitado.
- Los límites de 40 000 componentes y 100 000 peticiones diarias son holgados para el volumen previsto
  de HU-01/HU-02, aunque no se han medido.
- **Telemetría:** el EULA dice que el producto envía información de uso. No se ha verificado si la
  instancia actual la envía antes de aceptarlo.
- **Pruebas de seguridad:** el EULA prohíbe hacer pruebas de seguridad *sobre el producto*. Las
  comprobaciones de `verify-infra.sh` son funcionales (estado de la API, que pida autenticación y que
  no esté expuesto), pero el equipo debería confirmar que encajan en lo permitido.
- **Uso:** «internal business purposes» en un proyecto universitario es una cuestión de
  interpretación que el equipo (o su institución) debe valorar.

## 3. Consecuencias para el proyecto

| Opción | Efecto en HU-01 | Efecto en historias posteriores |
|---|---|---|
| **No aceptar** (estado actual) | C1 y C5 quedan en **PARTIAL** por Nexus: desplegado y preparado, sin función de repositorio | Jenkins no puede publicar imágenes en Nexus; haría falta otro registro |
| **Aceptar** (decisión del equipo) | Completar Nexus con una ejecución de `bootstrap-nexus.sh` (arranque facturable, ≈ 0.10 USD/h) | El repositorio Docker queda disponible; se asumen la telemetría y los límites de Community Edition |
| **Otro producto** | Requiere cambiar el stack y su documentación | Fuera del alcance de HU-01 |

## 4. Recomendación técnica y contractual (auditoría final del 2026-11-02; no es asesoramiento legal)

1. **Funciones pendientes:** descargar y subir componentes, el repositorio Docker `circleguard-docker`,
   el realm DockerToken y la configuración del acceso anónimo. Nexus ya está desplegado, en línea, con
   la contraseña del administrador gestionada y sin publicar el conector Docker.
2. **Si no se acepta:** Nexus no puede actuar como registro. HU-01 deja a Nexus **desplegado y
   preparado**, y C1 y C5 quedan en PARTIAL por esta decisión (C5 también por el ensayo de
   reconstrucción pendiente). Las historias que publiquen
   imágenes necesitarían el EULA aceptado o un registro alternativo.
3. **Uso académico:** el EULA limita el uso a «internal business purposes» y no menciona el uso
   educativo. Sonatype puede cambiar los términos y el uso continuado implica aceptarlos. Corresponde a
   la persona autorizada del equipo (o de la institución) decidir si un proyecto universitario encaja.
4. **Pruebas de seguridad:** el EULA prohíbe «penetration testing, vulnerability testing or other
   security testing on the Product». Quedarían excluidos, por ejemplo, escáneres de vulnerabilidades o
   pruebas de intrusión contra la interfaz o la API de Nexus. Las comprobaciones actuales de
   `verify-infra.sh` son funcionales (estado de la API, que exige autenticación y que no está expuesto),
   pero conviene que el equipo confirme que las considera permitidas.
5. **Telemetría:** el producto envía información de uso (técnica, estadística y de rendimiento, que
   puede incluir la IP) y no se puede restringir. Para un servidor de la universidad es un dato que la
   institución puede querer conocer. No se ha verificado si la instancia actual ya la envía antes de
   aceptar el EULA.
6. **Recomendación:** **esperar la decisión** de la persona autorizada, sin aceptarlo por defecto.
   Nexus está ya preparado, de modo que aceptarlo después solo exige una ejecución. Si el equipo no
   puede aceptar esas condiciones, conviene **sustituirlo** antes de las historias que publiquen
   imágenes.
7. **Cambios según la alternativa:**

| Alternativa | Cambios técnicos | Cambios documentales | Coste |
|---|---|---|---|
| Aceptar | `NEXUS_ACCEPT_EULA=true` (con su commit); arrancar `circleguard-nexus`; `bash infra/bootstrap-nexus.sh --apply`; `verify-infra.sh` debe pasar el EULA a PASS y comprobar el registro Docker | Evidencias 14 y 16 y README de evidencias: C1 y C5 sin la limitación de Nexus; registrar quién aceptó y cuándo | Una sesión corta con `nexus` encendida (≈ 0.10 USD/h) |
| Esperar (estado actual) | Ninguno | Mantener «desplegado y preparado, EULA pendiente» | 0 (más el EBS de la instancia detenida) |
| Sustituir (por ejemplo, el registro de CNCF Distribution o Harbor, ambos con licencia Apache 2.0). **Nota posterior (2026-11-03):** CNCF Distribution queda preparado como registro **junto a** Nexus, sin retirarlo (`REGISTRY_BACKEND`, [registro-artefactos.md](../../arquitectura/registro-artefactos.md)), y no requiere aceptar este EULA. Falta desplegarlo en AWS | Nuevo stack Compose y su bootstrap; revisar los puertos 8081 y 8082 de los grupos de seguridad; adaptar `verify-infra.sh`, `tunnel.sh` y los secretos de `secrets.catalog`; retirar o conservar Nexus | Arquitectura, README de infraestructura y evidencias; justificar el cambio de herramienta frente al enunciado de HU-01, que pide Nexus | Desarrollo y una sesión de prueba (≈ 0.10 USD/h); fuera del alcance de HU-01 |
