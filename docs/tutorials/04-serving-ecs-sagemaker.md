# 04 Serving ECS and SageMaker

## Objetivo y contexto
Publicar inferencia de forma controlada con endpoint de SageMaker y, si aplica, capa de servicio en ECS/Fargate.

## Decisiones tecnicas y alternativas descartadas
- Endpoint update solo con modelo validado/registrado.
- Estrategia de despliegue:
  - desplegar primero a endpoint `staging`,
  - correr smoke tests,
  - promover a endpoint `prod` solo con gate manual.
- ECS opcional para API o integracion adicional.
- Alternativas descartadas: update directo sin gate.

## IAM usado (roles/policies/permisos clave)
- SageMaker endpoint roles.
- ECS task execution/task role con permisos minimos.
- Operador humano con usuario `data-science-user` y keys logicas `data-science-user-primary` / `data-science-user-rotation`.

## Comandos ejecutados y resultado esperado
- Regla operativa AWS: ejecutar comandos con `data-science-user` como base y perfiles `data-science-user-dev` (dev) o `data-science-user-prod` (prod).
- `terraform plan` del modulo de serving
- Deploy de endpoint `staging` con modelo registrado
- Smoke tests de inferencia sobre `staging`
- Deploy a `prod` solo tras aprobacion manual
- Resultado esperado: `staging` y `prod` estables, respuesta valida y rollout controlado.

## Evidencia
Agregar:
- Endpoint names/ARN de `staging` y `prod`.
- Resultados de smoke tests en `staging`.
- Evidencia de aprobacion manual para despliegue a `prod`.
- Latencia base y tasa de error inicial.

## Riesgos/pendientes
- Sobreaprovisionamiento de instancias.
- Falta de rollback rapido de endpoint.

## Proximo paso
Conectar CI/CD en `docs/tutorials/05-cicd-github-actions.md`.
