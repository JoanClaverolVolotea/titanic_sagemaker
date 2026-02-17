# 02 Training and Validation

## Objetivo y contexto
Entrenar modelo con Titanic y validar metricas para definir umbral de promocion.

## Paso a paso (ejecucion)
1. Confirmar rutas S3 de `train.csv` y `validation.csv` (salida de fase 01).
2. Definir metrica principal y umbral de promocion (ejemplo `accuracy >= 0.78`).
3. Validar infraestructura del modulo de entrenamiento:
   - `terraform fmt -check`
   - `terraform validate`
   - `terraform plan`
4. Ejecutar training job en SageMaker con perfil `data-science-user`.
5. Ejecutar evaluacion sobre validation set.
6. Persistir metricas y emitir decision binaria de calidad:
   - `pass`: candidato a registro,
   - `fail`: volver a iterar en datos/modelo.

## Decisiones tecnicas y alternativas descartadas
- Definir split train/validation reproducible.
- Definir metrica principal para aprobacion de modelo.
- Definir umbral de promocion (ejemplo: `accuracy >= 0.78` en validation).
- Alternativas descartadas: despliegue sin validacion cuantitativa.

## IAM usado (roles/policies/permisos clave)
- SageMaker execution role con acceso minimo a S3/ECR/CloudWatch.
- Operador humano con usuario `data-science-user` y keys logicas `data-science-user-primary` / `data-science-user-rotation`.

## Comandos ejecutados y resultado esperado
- Regla operativa AWS: ejecutar comandos con `data-science-user` como base y perfil `data-science-user`.
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

## Criterio de cierre
- Training job finalizado en estado exitoso.
- Metricas de validacion almacenadas y trazables.
- Existe decision de promocion documentada (`pass`/`fail`).

## Riesgos/pendientes
- Drift entre dataset usado y dataset versionado.
- Falta de trazabilidad de hiperparametros.

## Proximo paso
Automatizar flujo con SageMaker Pipeline en `docs/tutorials/03-sagemaker-pipeline.md`.
