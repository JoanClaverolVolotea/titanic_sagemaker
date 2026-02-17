# 03 SageMaker Pipeline

## Objetivo y contexto
Construir pipeline de SageMaker para procesamiento, entrenamiento, evaluacion y registro de modelo.

## Paso a paso (ejecucion)
1. Definir pipeline con 4 pasos obligatorios:
   - `DataPreProcessing`
   - `TrainModel`
   - `ModelEvaluation`
   - `RegisterModel`
2. Validar y planificar IaC del modulo de pipeline:
   - `terraform fmt -check`
   - `terraform validate`
   - `terraform plan`
3. Publicar o actualizar definición del pipeline en SageMaker.
4. Ejecutar `start-pipeline-execution` con input de datos de fase 01.
5. Revisar estado de cada paso y logs asociados.
6. Verificar que el modelo quedó en `SageMaker Model Registry` con metadatos de evaluación.
7. Configurar trigger programado (EventBridge/Step Functions) para ejecuciones periódicas.

## Decisiones tecnicas y alternativas descartadas
- Pipeline declarativo con pasos versionados.
- Registro obligatorio de modelo antes de deployment.
- Pasos objetivo del pipeline:
  - `DataPreProcessing` (SageMaker Processing Job)
  - `TrainModel` (SageMaker Training Job)
  - `ModelEvaluation` (SageMaker Processing Job)
  - `RegisterModel` (Model Registry)
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
  - paquete de modelo registrado en `SageMaker Model Registry`,
  - estado de aprobacion inicial controlado por criterio de validacion.

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
