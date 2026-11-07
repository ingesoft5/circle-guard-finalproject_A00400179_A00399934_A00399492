# Registro de uso de IA generativa (IAG)

Este directorio conserva, para cada historia de usuario, los **prompts** enviados a la IA, una
síntesis de las **respuestas** y las **decisiones** tomadas con su justificación. El proyecto usa
el **Nivel 3 (colaboración con IAG)** descrito en `Proyecto_Final_CircleGuard.tex`: la IA apoya el
trabajo, pero el equipo revisa, entiende y puede explicar cada resultado.

## Reglas

- No se guardan secretos, contraseñas, tokens ni rutas personales sensibles.
- Cada sesión tiene fecha, rama, herramienta y modelo.
- Cada decisión tiene contexto, alternativas, decisión y consecuencias.
- Los archivos generados se enlazan desde la sesión.
- El registro se versiona con el código; no se edita retroactivamente (si una decisión cambia, se
  añade una nueva entrada que reemplaza a la anterior).

## Índice

| Fecha | Historia | Sesión | Decisiones |
|---|---|---|---|
| 2026-11-02 | HU-02 · Imágenes Docker inmutables | [Sesión](sesiones/2026-11-02-hu-02.md) | [D-01 a D-11](decisiones.md) |
| 2026-11-05 | HU-06 · Entrega continua y promoción | [Sesión](sesiones/2026-11-05-hu-06.md) | [D-12 a D-25](decisiones.md) (D-21/D-22 en HU-07) |

## Plantilla

Use [`plantilla-sesion.md`](plantilla-sesion.md) para las próximas historias.
