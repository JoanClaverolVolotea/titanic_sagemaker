# 05 CI/CD GitHub Actions

## Objetivo y contexto
Automatizar validaciones y despliegues de infraestructura/modelo desde GitHub.

## Decisiones tecnicas y alternativas descartadas
- PR: checks obligatorios (lint/test/validate/plan/security).
- `ModelBuild` pipeline: construir/validar y ejecutar SageMaker Pipeline para registrar modelo.
- `ModelDeploy` pipeline: desplegar `staging`, ejecutar smoke tests y promover a `prod` con aprobacion manual.
- Merge a main: deploy a `dev` + smoke tests.
- Promocion a `prod`: aprobacion manual via GitHub Environment protection rules.
- Equivalencia con arquitectura de referencia:
  - Source/Build/Deploy separados logicamente,
  - registry como contrato entre build y deploy.

## IAM usado (roles/policies/permisos clave)
- OIDC o credenciales seguras para GitHub Actions.
- Roles por entorno con permisos minimos y `PassRole` restringido.
- Operador humano con usuario `data-science-user` y keys logicas `data-science-user-primary` / `data-science-user-rotation`.

## Comandos ejecutados y resultado esperado
- Regla operativa AWS: ejecutar comandos con `data-science-user` como base y perfiles `data-science-user-dev` (dev) o `data-science-user-prod` (prod).
- Ejecucion workflow `model-build.yml` en PR/main:
  - checks + terraform plan + trigger de SageMaker Pipeline.
- Ejecucion workflow `model-deploy.yml`:
  - despliegue a `staging`,
  - smoke test,
  - aprobacion manual,
  - despliegue a `prod`.
- Resultado esperado: gates aplicados, deploy reproducible y promocion controlada.

## Evidencia
Agregar:
- Links a runs de `ModelBuild` y `ModelDeploy`.
- Plan/apply por entorno.
- Evidencia de aprobacion manual en release a `prod`.
- Resultado de smoke tests de `staging`.

## Riesgos/pendientes
- Secretos mal gestionados.
- Falta de bloqueos por drift o cambios no aprobados.

## Proximo paso
Completar observabilidad en `docs/tutorials/06-observability-operations.md`.
