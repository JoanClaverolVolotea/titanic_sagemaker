# 04 Serving ECS and SageMaker

## Objetivo y contexto
Publicar inferencia de forma controlada con endpoint de SageMaker y, si aplica, capa de servicio en ECS/Fargate.

## Decisiones tecnicas y alternativas descartadas
- Endpoint update solo con modelo validado/registrado.
- ECS opcional para API o integracion adicional.
- Alternativas descartadas: update directo sin gate.

## IAM usado (roles/policies/permisos clave)
- SageMaker endpoint roles.
- ECS task execution/task role con permisos minimos.

## Comandos ejecutados y resultado esperado
- `terraform plan` del modulo de serving
- Smoke tests de inferencia
- Resultado esperado: endpoint estable y respuesta valida.

## Evidencia
Agregar endpoint name/ARN, resultados de smoke test y latencia base.

## Riesgos/pendientes
- Sobreaprovisionamiento de instancias.
- Falta de rollback rapido de endpoint.

## Proximo paso
Conectar CI/CD en `docs/tutorials/05-cicd-github-actions.md`.
