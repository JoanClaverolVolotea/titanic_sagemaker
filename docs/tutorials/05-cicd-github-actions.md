# 05 CI/CD GitHub Actions

## Objetivo y contexto
Automatizar validaciones y despliegues de infraestructura/modelo desde GitHub.

## Decisiones tecnicas y alternativas descartadas
- PR: checks obligatorios (lint/test/validate/plan/security).
- Merge a main: deploy a `dev` + smoke tests.
- Promocion a `prod`: aprobacion manual.

## IAM usado (roles/policies/permisos clave)
- OIDC o credenciales seguras para GitHub Actions.
- Roles por entorno con permisos minimos y `PassRole` restringido.
- Operador humano con usuario `data-science-user` y keys logicas `data-science-user-primary` / `data-science-user-rotation`.

## Comandos ejecutados y resultado esperado
- Regla operativa AWS: ejecutar comandos con `data-science-user` como base y perfiles `data-science-user-dev` (dev) o `data-science-user-prod` (prod).
- Ejecucion de workflows en PR y main
- Resultado esperado: gates aplicados y despliegue reproducible.

## Evidencia
Agregar links a runs de GitHub Actions, planes/applies y resultados de pruebas.

## Riesgos/pendientes
- Secretos mal gestionados.
- Falta de bloqueos por drift o cambios no aprobados.

## Proximo paso
Completar observabilidad en `docs/tutorials/06-observability-operations.md`.
