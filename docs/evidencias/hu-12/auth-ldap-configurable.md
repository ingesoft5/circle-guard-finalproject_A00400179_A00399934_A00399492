# Evidencia · auth: la conexión LDAP sale de la configuración externa (HU-12, 2026-11-20)

## Problema
[SecurityConfig.java](../../../services/circleguard-auth-service/src/main/java/com/circleguard/auth/security/SecurityConfig.java) fijaba en el código `ldap://localhost:389`, la base, el usuario y la contraseña `admin`. En un contenedor eso ignoraba `SPRING_LDAP_URLS` y `LDAP_ADMIN_PASSWORD` de Compose: auth no podía llegar a OpenLDAP y `/actuator/health` (HU-13) daba **DOWN [503]** por el indicador de LDAP. Además había una contraseña escrita en el código.

## Cambio
El bean `contextSource` recibe `spring.ldap.urls`, `spring.ldap.base`, `spring.ldap.username` y `spring.ldap.password` (ya declarados en `application.yml`; Compose los sobrescribe con `SPRING_LDAP_URLS` y `LDAP_ADMIN_PASSWORD`). La contraseña no tiene valor por defecto: sin ella la aplicación no arranca, en vez de usar una conocida. Comportamiento de login sin cambios: LDAP primero y, si lo rechaza, base local.

## Verificación
- Pruebas unitarias de auth: **59 pruebas, 0 fallos** (SecurityConfigTest pasa de 5 a 6 casos: configuración externa respetada, la contraseña no está fija) y la verificación de cobertura de JaCoCo en verde.
- Imagen reconstruida (`1.0.0-hu12ldap`; las otras ocho son las mismas de `1.0.0-hu14fix`) y pila Compose completa: **15/15 healthy**.
- `auth` `/actuator/health` → `{"status":"UP",...} [200]` (antes DOWN [503]).
- Login del usuario sembrado a través del proxy web → 200 (con token); contraseña incorrecta → 401; identity vía proxy → 200 UP.
- Observación: la **primera** llamada de login tras arrancar dio **503** `Identity service unavailable, please retry shortly` (tiempo de lectura de 3 s superado en frío; el log de auth lo registra desde `LoginController`, es el fallback del circuit breaker funcionando). Las siguientes tres dieron 200. No se cambió el timeout.
- Solo aparecen como ERROR en el log los avisos del exportador OTLP (no hay colector en este stack).
