# Hallazgo H1 · el QR caduca a los 300 ms (HU-15)

**Qué se observó.** Con la configuración del repositorio, la validación de acceso rechazaba tokens recién generados.

| Prueba | Resultado con la configuración del repositorio | Resultado con `QR_EXPIRATION=60000` |
|---|---|---|
| Prueba de humo de Locust, 10 usuarios, 30 s ([evaluation](smoke-con-configuracion-del-repositorio.md), [fallos](smoke-fallos.csv)) | **244 de 304** validaciones rechazadas (80,26 %): «the gate denied a valid token» | — |
| 40 generaciones de QR seguidas de su validación, un solo cliente (sonda) | 14 válidas y **26** `RED · Invalid or Expired Token` | **40 de 40** `GREEN · Welcome to Campus` |
| Corrida definitiva (10, 50 y 100 usuarios, 5 min) | — | 0,00 % de errores en todos los escalones |

**Causa.** [application.yml](../../../../services/circleguard-auth-service/src/main/resources/application.yml) de auth define `qr.expiration: 300`; `QrTokenService` suma ese valor a `System.currentTimeMillis()`, es decir **300 milisegundos**.
El valor por defecto del código es 60000, el controlador responde `"expiresIn": "60"` y el cliente web usa 60 segundos. Un token solo es válido si se valida dentro de los 300 ms siguientes a su emisión; con carga o latencia deja de serlo.

**Qué se hizo y qué no.** No se modificó el código ni la configuración de auth (es de otra historia). Para medir el flujo con la expiración prevista, el contenedor `auth` de la pila **local** se recreó con la variable
`QR_EXPIRATION=60000` mediante un archivo de Compose temporal fuera del repositorio. Acción propuesta: corregir el valor o la unidad en auth y añadir una prueba que fije la expiración.

La sonda y la comparación se hicieron en la misma pila y con el mismo usuario sembrado; los valores de contraseña no se imprimen ni se guardan.
