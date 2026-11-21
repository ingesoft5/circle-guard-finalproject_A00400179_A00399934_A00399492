# Evidencia · Excepciones de vulnerabilidades con caducidad (HU-14, FASE 9)

Salida real de `security/scan-images.sh --evaluate security/tests/fixtures/exceptions-report.json --class own --scope test-image`, con un informe **sintético** (un CRITICAL y un HIGH) y la fecha fijada con `EXCEPTIONS_TODAY=2026-11-20`. Reglas: [FASE 9](../../seguridad/hu-14.md#fase-9--excepciones-de-vulnerabilidades-con-caducidad).

## 1. Excepciones vigentes: la compuerta pasa

```
    excepción vigente: SYNTHETIC-0101 example.org:lib-a (CRITICAL) responsable alice@example.org, caduca 2026-12-05
    excepción vigente: SYNTHETIC-0102 example.org:lib-b (HIGH) responsable bob@example.org, caduca 2027-01-20
PASS        own           C=1    H=1    M=0    L=0    U=0     fixtures/exceptions-report.json [excepciones vigentes: 2]
exit code: 0
```

Los contadores siguen mostrando el CRITICAL y el HIGH: la excepción no oculta nada.

## 2. Excepción CRITICAL caducada ayer: vuelve a bloquear

```
AVISO excepción CADUCADA, ya no es válida y la puerta vuelve a bloquear: SYNTHETIC-0101 example.org:lib-a [test-image] (expiró 2026-11-19, responsable alice@example.org)
    excepción vigente: SYNTHETIC-0102 example.org:lib-b (HIGH) responsable bob@example.org, caduca 2027-01-20
FAIL        own           C=1    H=1    M=0    L=0    U=0     fixtures/exceptions-report.json [excepciones vigentes: 1]
RESULT: FAIL · 1 image(s) exceed the threshold (CRITICAL,HIGH). Promotion must stop.
exit code: 1
```

## 3. Vulnerabilidad nueva sin excepción: bloquea

Solo el HIGH está exceptuado; el CRITICAL no tiene excepción.

```
    excepción vigente: SYNTHETIC-0102 example.org:lib-b (HIGH) responsable bob@example.org, caduca 2027-01-20
FAIL        own           C=1    H=1    M=0    L=0    U=0     fixtures/exceptions-report.json [excepciones vigentes: 1]
RESULT: FAIL · 1 image(s) exceed the threshold (CRITICAL,HIGH). Promotion must stop.
exit code: 1
```

## Pruebas

`bash security/tests/test-exceptions.sh` → `29 passed, 0 failed`; `bash security/tests/test-gate.sh` → `14 passed, 0 failed` (la compuerta anterior no cambió). Los responsables de estos ejemplos (`alice@`, `bob@example.org`) son ficticios y solo existen en las pruebas.
