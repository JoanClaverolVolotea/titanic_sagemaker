# 03 SageMaker Pipeline

## Objetivo y contexto
Construir pipeline de SageMaker para procesamiento, entrenamiento, evaluacion y registro de modelo.
Esta fase convierte el ensayo manual de fase 02 en un flujo automatizado de `ModelBuild`.

## Paso a paso (ejecucion)
1. Importar contrato de entrada desde fase 02:
   - URIs `train_xgb.csv` y `validation_xgb.csv`,
   - threshold de calidad `accuracy >= 0.78`,
   - hiperparametros base validados.
2. Definir pipeline con 4 pasos obligatorios:
   - `DataPreProcessing`
   - `TrainModel`
   - `ModelEvaluation`
   - `RegisterModel`
3. Configurar condicion de registro:
   - solo ejecutar `RegisterModel` cuando `ModelEvaluation` cumpla el umbral.
   - registrar el paquete en `PendingManualApproval` para habilitar gate humano antes de deploy.
4. Validar y planificar IaC del modulo de pipeline:
   - `terraform fmt -check`
   - `terraform validate`
   - `terraform plan`
5. Publicar o actualizar definición del pipeline en SageMaker.
6. Ejecutar `start-pipeline-execution` con input de datos de fase 01/02.
7. Revisar estado de cada paso y logs asociados.
8. Verificar que el modelo quedó en `SageMaker Model Registry` con metadatos de evaluación.
9. Configurar trigger programado (EventBridge/Step Functions) para ejecuciones periódicas.

## Decisiones tecnicas y alternativas descartadas
- Pipeline declarativo con pasos versionados.
- Registro obligatorio de modelo antes de deployment.
- Pasos objetivo del pipeline:
  - `DataPreProcessing` (SageMaker Processing Job)
  - `TrainModel` (SageMaker Training Job)
  - `ModelEvaluation` (SageMaker Processing Job)
  - `RegisterModel` (Model Registry)
- `RegisterModel` condicionado por metricas para mantener paridad con el gate de calidad de fase 02.
- `ModelApprovalStatus` inicial en `PendingManualApproval` para encadenar con el gate de despliegue.
- Trigger por scheduler/orquestacion para ejecuciones periodicas.
- Alternativas descartadas: jobs sueltos no orquestados.

## IAM usado (roles/policies/permisos clave)
- Permisos para crear/ejecutar pipeline y registrar modelos.
- Operador humano con usuario `data-science-user` y keys logicas `data-science-user-primary` / `data-science-user-rotation`.

## Comandos ejecutados y resultado esperado
- Regla operativa AWS: ejecutar comandos con `data-science-user` como base y perfil `data-science-user`.
- `terraform plan` del modulo de pipeline
- Publicar/actualizar pipeline en SageMaker
- Ejecutar pipeline (`start-pipeline-execution`)
- Resultado esperado:
  - pasos `DataPreProcessing`, `TrainModel`, `ModelEvaluation` completados,
  - registro condicional en `SageMaker Model Registry` cuando pase umbral,
  - estado de aprobacion inicial `PendingManualApproval`.

## Evidencia
Agregar:
- `PipelineExecutionArn`.
- Estado de cada paso.
- `ModelPackageArn` registrado y estado de aprobacion.

## Criterio de cierre
- Pipeline ejecuta de punta a punta sin errores.
- Se registra un `ModelPackageArn` válido en registry.
- Queda definido el mecanismo de trigger periódico para nuevas ejecuciones.

## Riesgos/pendientes
- Falta de criterio de aprobacion automatico.
- Errores de permisos en pasos intermedios.

## Proximo paso
Definir serving con ECS/SageMaker endpoint en `docs/tutorials/04-serving-ecs-sagemaker.md`.
