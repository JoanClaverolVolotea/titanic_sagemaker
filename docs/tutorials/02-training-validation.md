# 02 Training and Validation

## Objetivo y contexto
Entrenar modelo con Titanic y validar metricas para definir umbral de promocion.

## Decisiones tecnicas y alternativas descartadas
- Definir split train/validation reproducible.
- Definir metrica principal para aprobacion de modelo.
- Definir umbral de promocion (ejemplo: `accuracy >= 0.78` en validation).
- Alternativas descartadas: despliegue sin validacion cuantitativa.

## IAM usado (roles/policies/permisos clave)
- SageMaker execution role con acceso minimo a S3/ECR/CloudWatch.
- Operador humano con usuario `data-science-user` y keys logicas `data-science-user-primary` / `data-science-user-rotation`.

## Comandos ejecutados y resultado esperado
- Regla operativa AWS: ejecutar comandos con `data-science-user` como base y perfiles `data-science-user-dev` (dev) o `data-science-user-prod` (prod).
- `terraform plan` del modulo de entrenamiento
- Trigger de training job
- Ejecutar evaluacion con validation set
- Resultado esperado:
  - training job exitoso,
  - metricas persistidas (`accuracy`, `f1`, `precision`, `recall`),
  - decision binaria de promocion (`pass`/`fail`) para la fase de registry.

## Evidencia
Agregar:
- Job ARN.
- Metricas finales en validation.
- Umbral aplicado y resultado (`pass`/`fail`).
- Ubicacion S3 del modelo generado.

## Riesgos/pendientes
- Drift entre dataset usado y dataset versionado.
- Falta de trazabilidad de hiperparametros.

## Proximo paso
Automatizar flujo con SageMaker Pipeline en `docs/tutorials/03-sagemaker-pipeline.md`.
