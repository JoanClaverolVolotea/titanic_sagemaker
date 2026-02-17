# 03 SageMaker Pipeline

## Objetivo y contexto
Construir pipeline de SageMaker para procesamiento, entrenamiento, evaluacion y registro de modelo.

## Decisiones tecnicas y alternativas descartadas
- Pipeline declarativo con pasos versionados.
- Registro obligatorio de modelo antes de deployment.
- Alternativas descartadas: jobs sueltos no orquestados.

## IAM usado (roles/policies/permisos clave)
- Permisos para crear/ejecutar pipeline y registrar modelos.

## Comandos ejecutados y resultado esperado
- `terraform plan` del modulo de pipeline
- Ejecucion del pipeline
- Resultado esperado: pipeline completo y modelo en registry.

## Evidencia
Agregar execution ID, estado de pasos y version registrada.

## Riesgos/pendientes
- Falta de criterio de aprobacion automatico.
- Errores de permisos en pasos intermedios.

## Proximo paso
Definir serving con ECS/SageMaker endpoint en `docs/tutorials/04-serving-ecs-sagemaker.md`.
