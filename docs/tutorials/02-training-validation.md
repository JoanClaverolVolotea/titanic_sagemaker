# 02 Training and Validation

## Objetivo y contexto
Entrenar modelo con Titanic y validar metricas para definir umbral de promocion.

## Decisiones tecnicas y alternativas descartadas
- Definir split train/validation reproducible.
- Definir metrica principal para aprobacion de modelo.
- Alternativas descartadas: despliegue sin validacion cuantitativa.

## IAM usado (roles/policies/permisos clave)
- SageMaker execution role con acceso minimo a S3/ECR/CloudWatch.

## Comandos ejecutados y resultado esperado
- `terraform plan` del modulo de entrenamiento
- Trigger de training job
- Resultado esperado: job exitoso, metricas persistidas.

## Evidencia
Agregar Job ARN, metricas finales y ubicacion del modelo generado.

## Riesgos/pendientes
- Drift entre dataset usado y dataset versionado.
- Falta de trazabilidad de hiperparametros.

## Proximo paso
Automatizar flujo con SageMaker Pipeline en `docs/tutorials/03-sagemaker-pipeline.md`.
