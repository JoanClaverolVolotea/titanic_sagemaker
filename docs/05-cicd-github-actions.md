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

## Comandos ejecutados y resultado esperado
- Ejecucion de workflows en PR y main
- Resultado esperado: gates aplicados y despliegue reproducible.

## Evidencia
Agregar links a runs de GitHub Actions, planes/applies y resultados de pruebas.

## Riesgos/pendientes
- Secretos mal gestionados.
- Falta de bloqueos por drift o cambios no aprobados.

## Proximo paso
Completar observabilidad en `docs/06-observability-operations.md`.
