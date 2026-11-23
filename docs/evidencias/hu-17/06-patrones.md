# Patrones de diseño (HU-12) — enlaces y trade-offs

**Estado:** implementado en el PR #14 y corregido en el PR #20. Documento dueño:
[`../../arquitectura/patrones-diseno.md`](../../arquitectura/patrones-diseno.md).

| Patrón | Dónde vive | Prueba |
|---|---|---|
| Circuit Breaker | `services/circleguard-auth-service/src/main/java/com/circleguard/auth/client/IdentityClient.java` | `IdentityClientTest` + falla inyectada en HU-14 |
| External Configuration | `IdentityClientProperties.java` y `application.yml` | `IdentityClientTest` |
| Dead Letter Topic | `KafkaErrorHandlingConfig` en `promotion` y `notification` | `DeadLetterTopicIntegrationTest` |

## Por qué estos patrones

- **Circuit Breaker:** si `identity` cae, `auth` debe fallar rápido y no arrastrar al resto. No hay
  *fallback* que invente un `anonymousId`: rompería la anonimización.
- **External Configuration:** el cliente de identidad se configura por entorno (`SPRING_LDAP_*`,
  URL y timeouts) sin recompilar.
- **Dead Letter Topic:** un mensaje inválido no se pierde ni bloquea la partición; se reintenta y
  termina en el DLT con su causa.

## Evidencias

- [`../hu-12/evidencias-hu12.md`](../hu-12/evidencias-hu12.md)
- [`../hu-12/auth-ldap-configurable.md`](../hu-12/auth-ldap-configurable.md)
- [`../../revisiones/hu-12-revision.md`](../../revisiones/hu-12-revision.md)

## Trade-offs

| Patrón | Costo | Beneficio |
|---|---|---|
| Circuit Breaker | Un estado más que operar y explicar | Evita cascadas y da tiempo a recuperar |
| External Configuration | Más variables que documentar | Cambios por ambiente sin recompilar |
| DLT | Un topic y un consumidor más | No se pierden eventos y se audita la causa |
