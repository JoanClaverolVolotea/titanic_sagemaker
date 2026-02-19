# 03 SageMaker Pipeline

## Objetivo y contexto
Construir el flujo MLOps canonico de `ModelBuild` en SageMaker Pipeline:
`DataPreProcessing -> TrainModel -> ModelEvaluation -> RegisterModel`.

Esta fase se ejecuta 100% en SageMaker gestionado:
1. SageMaker orquesta y ejecuta los steps.
2. Los datos de entrada viven en S3 (`curated/*`).
3. El codigo Python se versiona en el repositorio y CI lo publica como artefacto en S3.
4. No se usa contenedor propio en ECR en esta fase.

Entradas externas unicas de datos:
1. `s3://.../curated/train.csv`
2. `s3://.../curated/validation.csv`

## Resultado minimo esperado al cerrar esta fase
1. Infraestructura Terraform de fase 03 creada y versionada.
2. Pipeline de SageMaker publicado y ejecutable.
3. Ejecucion de pipeline con pasos completados en orden.
4. Registro de modelo en Model Registry cuando cumple el umbral (`accuracy >= 0.78`).

## Recursos necesarios y quien los crea
| Recurso | Servicio | Lo crea CI/CD | Lo crea Terraform | Lo crea la ejecucion del pipeline | Proposito |
|---|---|---|---|---|---|
| Bucket/prefijos de datos (`raw/`, `curated/`) | S3 | No | No (viene de fase 00/01) | No | Input externo del pipeline |
| Artefacto de codigo (`pipeline_code.tar.gz`) | S3 | Si | No | No | Codigo Python versionado para steps del pipeline |
| Prefijos de artefactos runtime | S3 | No | Opcional (solo convencion) | Si | Salidas internas de pasos |
| Role de ejecucion del pipeline | IAM | No | Si | No | Permisos para Processing/Training/Evaluation/Register |
| Politica del role (S3 + SageMaker + CloudWatch) | IAM | No | Si | No | Least-privilege del pipeline |
| Model Package Group | SageMaker | No | Si | No | Contenedor logico de versiones de modelo |
| Definicion de pipeline | SageMaker | No | Si (`aws_sagemaker_pipeline`) | No | Orquestacion de los 4 pasos |
| Processing Job | SageMaker | No | No | Si | Preprocesar `curated/*` dentro del pipeline |
| Training Job | SageMaker | No | No | Si | Entrenar modelo |
| Evaluation Job | SageMaker | No | No | Si | Calcular metricas y emitir reporte |
| Model Package version | SageMaker Model Registry | No | No | Si | Registro condicional del modelo |
| Trigger programado (opcional) | EventBridge / Scheduler | No | Si (fase 06 idealmente) | No | Ejecucion periodica |

## Flujo repo -> CI -> S3 -> SageMaker Pipeline
1. Commit en GitHub.
2. CI empaqueta `pipeline/code/` en `pipeline_code.tar.gz`.
3. CI sube el artefacto a `s3://$DATA_BUCKET/pipeline/code/$GIT_SHA/pipeline_code.tar.gz`.
4. Terraform publica/actualiza SageMaker Pipeline usando `code_bundle_uri`.
5. `start-pipeline-execution` se lanza con `CodeBundleUri` + `InputTrainUri` + `InputValidationUri`.
6. SageMaker ejecuta `DataPreProcessing -> TrainModel -> ModelEvaluation -> RegisterModel`
   y registra modelo solo si pasa el umbral de calidad.

## Como se suben los scripts de Python
Estructura esperada del codigo en repo:
1. `pipeline/code/preprocess.py`
2. `pipeline/code/train.py` (si aplica)
3. `pipeline/code/evaluate.py`
4. `pipeline/code/requirements.txt` (si aplica)

Empaquetado y subida del artefacto:
```bash
export AWS_PROFILE=data-science-user
export AWS_REGION=eu-west-1
export DATA_BUCKET=$(terraform -chdir=terraform/00_foundations output -raw data_bucket_name)
export GIT_SHA=$(git rev-parse --short HEAD)

tar -czf pipeline_code.tar.gz pipeline/code/

aws s3 cp pipeline_code.tar.gz \
  s3://$DATA_BUCKET/pipeline/code/$GIT_SHA/pipeline_code.tar.gz \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION"
```

## Como se crearan los modelos con Terraform (punto clave)
Terraform en fase 03 no crea versiones de modelo una a una.

Terraform crea:
1. La infraestructura estable:
   - role/policies,
   - model package group,
   - pipeline definition.
2. El contrato de ejecucion:
   - parametros de input (`curated/train.csv`, `curated/validation.csv`),
   - parametro `CodeBundleUri` para el artefacto de codigo en S3,
   - umbral de calidad,
   - reglas de registro.

La ejecucion del pipeline crea dinamicamente:
1. Artefacto de entrenamiento en S3.
2. Metricas de evaluacion.
3. Nueva version de `ModelPackage` en Model Registry (si pasa umbral).

## Estructura Terraform recomendada para fase 03
Crear modulo nuevo:
- `terraform/03_sagemaker_pipeline/versions.tf`
- `terraform/03_sagemaker_pipeline/providers.tf`
- `terraform/03_sagemaker_pipeline/variables.tf`
- `terraform/03_sagemaker_pipeline/locals.tf`
- `terraform/03_sagemaker_pipeline/iam.tf`
- `terraform/03_sagemaker_pipeline/sagemaker_pipeline.tf`
- `terraform/03_sagemaker_pipeline/model_registry.tf`
- `terraform/03_sagemaker_pipeline/outputs.tf`
- `terraform/03_sagemaker_pipeline/pipeline_definition.json.tpl`
- `terraform/03_sagemaker_pipeline/terraform.tfvars.example`

## Variables de entrada recomendadas (`terraform.tfvars`)
- `aws_region = "eu-west-1"`
- `aws_profile = "data-science-user"`
- `environment = "dev"`
- `owner = "<team-or-user>"`
- `cost_center = "<value>"`
- `project_name = "titanic-sagemaker"`
- `data_bucket_name = "<output de terraform/00_foundations>"`
- `code_bundle_s3_prefix = "pipeline/code"`
- `code_bundle_uri = "s3://<bucket>/pipeline/code/<commit_sha>/pipeline_code.tar.gz"`
- `pipeline_name = "titanic-modelbuild-dev"`
- `model_package_group_name = "titanic-survival-xgboost"`
- `quality_threshold_accuracy = 0.78`
- `model_approval_status = "PendingManualApproval"`

## Paso a paso detallado (ejecucion + IaC)
1. Preparar contexto de ejecucion (shell + perfil + region):
   - objetivo: evitar ejecutar con perfil o region incorrecta.
   - ejecutar:
   ```bash
   set -euo pipefail
   export AWS_PROFILE=data-science-user
   export AWS_REGION=eu-west-1
   ```
   - validar:
   ```bash
   aws sts get-caller-identity --profile "$AWS_PROFILE"
   ```

2. Resolver bucket base desde fase 00:
   - objetivo: no hardcodear bucket en comandos/terraform.
   - ejecutar:
   ```bash
   export DATA_BUCKET=$(terraform -chdir=terraform/00_foundations output -raw data_bucket_name)
   echo "$DATA_BUCKET"
   ```
   - validar: el valor debe ser el bucket operativo del proyecto.

3. Verificar que inputs de datos existen (`curated/*`):
   - objetivo: bloquear temprano si fase 01 no esta completada.
   - ejecutar:
   ```bash
   aws s3 ls "s3://$DATA_BUCKET/curated/train.csv" --profile "$AWS_PROFILE" --region "$AWS_REGION"
   aws s3 ls "s3://$DATA_BUCKET/curated/validation.csv" --profile "$AWS_PROFILE" --region "$AWS_REGION"
   ```
   - validar: ambos objetos deben existir.

4. Preparar version de codigo por commit:
   - objetivo: trazabilidad y reproducibilidad.
   - ejecutar:
   ```bash
   export GIT_SHA=$(git rev-parse --short HEAD)
   echo "$GIT_SHA"
   ```
   - validar: `GIT_SHA` no vacio.

5. Validar estructura local de codigo del pipeline:
   - objetivo: evitar subir bundle incompleto.
   - revisar que existan:
     - `pipeline/code/preprocess.py`
     - `pipeline/code/train.py` (si aplica)
     - `pipeline/code/evaluate.py`
   - ejecutar:
   ```bash
   ls -la pipeline/code/
   ```

6. Empaquetar scripts Python del pipeline:
   - objetivo: generar artefacto inmutable consumible por SageMaker.
   - ejecutar:
   ```bash
   tar -czf pipeline_code.tar.gz pipeline/code/
   ```
   - validar:
   ```bash
   tar -tzf pipeline_code.tar.gz | head
   ```

7. Subir artefacto de codigo a S3:
   - objetivo: publicar codigo versionado para CI/CD y ejecucion.
   - ejecutar:
   ```bash
   aws s3 cp pipeline_code.tar.gz \
     "s3://$DATA_BUCKET/pipeline/code/$GIT_SHA/pipeline_code.tar.gz" \
     --profile "$AWS_PROFILE" \
     --region "$AWS_REGION"
   ```
   - validar:
   ```bash
   aws s3 ls "s3://$DATA_BUCKET/pipeline/code/$GIT_SHA/pipeline_code.tar.gz" \
     --profile "$AWS_PROFILE" \
     --region "$AWS_REGION"
   ```

8. Exportar `CodeBundleUri` para Terraform y ejecucion:
   - objetivo: pasar siempre la misma referencia de artefacto.
   - ejecutar:
   ```bash
   export CODE_BUNDLE_URI="s3://$DATA_BUCKET/pipeline/code/$GIT_SHA/pipeline_code.tar.gz"
   echo "$CODE_BUNDLE_URI"
   ```
   - validar: URI completa y con SHA del commit.

9. Preparar modulo Terraform de fase 03:
   - objetivo: definir infraestructura estable para pipeline.
   - estructura esperada:
     - `terraform/03_sagemaker_pipeline/versions.tf`
     - `terraform/03_sagemaker_pipeline/providers.tf`
     - `terraform/03_sagemaker_pipeline/variables.tf`
     - `terraform/03_sagemaker_pipeline/iam.tf`
     - `terraform/03_sagemaker_pipeline/sagemaker_pipeline.tf`
     - `terraform/03_sagemaker_pipeline/model_registry.tf`
     - `terraform/03_sagemaker_pipeline/pipeline_definition.json.tpl`
     - `terraform/03_sagemaker_pipeline/outputs.tf`

10. Configurar provider y tags obligatorios:
   - objetivo: cumplir gobierno de costos y trazabilidad.
   - `providers.tf` debe incluir `default_tags`:
     - `project=titanic-sagemaker`
     - `env=<dev|prod>`
     - `owner=<team-or-user>`
     - `managed_by=terraform`
     - `cost_center=<value>`

11. Crear role IAM del pipeline y trust policy:
   - objetivo: dar permisos de ejecucion a SageMaker sin usar permisos amplios.
   - trust principal esperado: `sagemaker.amazonaws.com`.
   - validar:
   ```bash
   aws iam get-role --role-name <pipeline_execution_role_name> --profile "$AWS_PROFILE"
   ```

12. Adjuntar policy least-privilege al role:
   - objetivo: permitir solo lo necesario.
   - permisos minimos:
     - `s3:GetObject` + `s3:ListBucket` en `curated/*`,
     - `s3:GetObject` en `pipeline/code/*`,
     - `s3:PutObject` en prefijos de artefactos,
     - logs en CloudWatch,
     - acciones SageMaker para processing/training/evaluation/register,
     - `iam:PassRole` acotado al role del pipeline.

13. Crear `Model Package Group`:
   - objetivo: centralizar versiones de modelo para promotion/deploy.
   - recurso Terraform: `aws_sagemaker_model_package_group`.
   - validar:
   ```bash
   aws sagemaker describe-model-package-group \
     --model-package-group-name <model_package_group_name> \
     --profile "$AWS_PROFILE" \
     --region "$AWS_REGION"
   ```

14. Definir `pipeline_definition.json.tpl` y `aws_sagemaker_pipeline`:
   - objetivo: materializar el flujo de 4 pasos.
   - parametros obligatorios en definicion:
     - `CodeBundleUri`
     - `InputTrainUri`
     - `InputValidationUri`
     - `AccuracyThreshold`
   - condicion de registro:
     - `RegisterModel` solo si `accuracy >= quality_threshold_accuracy`.

15. Ejecutar validaciones IaC (`init/fmt/validate/plan`):
   - objetivo: revisar diff tecnico y costo antes de aplicar.
   - ejecutar:
   ```bash
   terraform -chdir=terraform/03_sagemaker_pipeline init
   terraform -chdir=terraform/03_sagemaker_pipeline fmt -check
   terraform -chdir=terraform/03_sagemaker_pipeline validate
   terraform -chdir=terraform/03_sagemaker_pipeline plan \
     -var="data_bucket_name=$DATA_BUCKET" \
     -var="code_bundle_uri=$CODE_BUNDLE_URI"
   ```

16. Aplicar Terraform cuando el plan este aprobado:
   - objetivo: publicar pipeline/roles/model package group.
   - ejecutar:
   ```bash
   terraform -chdir=terraform/03_sagemaker_pipeline apply \
     -var="data_bucket_name=$DATA_BUCKET" \
     -var="code_bundle_uri=$CODE_BUNDLE_URI"
   ```
   - validar: `aws sagemaker describe-pipeline` devuelve ARN y definicion activa.

17. Lanzar ejecucion y monitorear fin a fin:
   - objetivo: confirmar que el pipeline corre con el codigo y datos esperados.
   - iniciar:
   ```bash
   aws sagemaker start-pipeline-execution \
     --pipeline-name titanic-modelbuild-dev \
     --region "$AWS_REGION" \
     --profile "$AWS_PROFILE" \
     --pipeline-parameters \
       Name=CodeBundleUri,Value="$CODE_BUNDLE_URI" \
       Name=InputTrainUri,Value="s3://$DATA_BUCKET/curated/train.csv" \
       Name=InputValidationUri,Value="s3://$DATA_BUCKET/curated/validation.csv" \
       Name=AccuracyThreshold,Value="0.78"
   ```
   - monitorear:
   ```bash
   aws sagemaker list-pipeline-executions \
     --pipeline-name titanic-modelbuild-dev \
     --region "$AWS_REGION" \
     --profile "$AWS_PROFILE"
   aws sagemaker list-pipeline-execution-steps \
     --pipeline-execution-arn <pipeline_execution_arn> \
     --region "$AWS_REGION" \
     --profile "$AWS_PROFILE"
   ```
   - validar cierre:
     - steps completados,
     - nueva version en `ModelPackageGroup`,
     - `ModelApprovalStatus=PendingManualApproval` si pasa umbral.

## Ejemplo de parametros de inicio del pipeline
```bash
aws sagemaker start-pipeline-execution \
  --pipeline-name titanic-modelbuild-dev \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --pipeline-parameters \
    Name=CodeBundleUri,Value="s3://$DATA_BUCKET/pipeline/code/$GIT_SHA/pipeline_code.tar.gz" \
    Name=InputTrainUri,Value="s3://$DATA_BUCKET/curated/train.csv" \
    Name=InputValidationUri,Value="s3://$DATA_BUCKET/curated/validation.csv" \
    Name=AccuracyThreshold,Value="0.78"
```

## Comandos Terraform minimos de fase 03
```bash
terraform -chdir=terraform/03_sagemaker_pipeline init
terraform -chdir=terraform/03_sagemaker_pipeline fmt -check
terraform -chdir=terraform/03_sagemaker_pipeline validate
terraform -chdir=terraform/03_sagemaker_pipeline plan
```

## Comandos de verificacion operativa
```bash
aws sagemaker describe-pipeline \
  --pipeline-name titanic-modelbuild-dev \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE"

aws sagemaker list-pipeline-executions \
  --pipeline-name titanic-modelbuild-dev \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE"
```

## Decisiones tecnicas y alternativas descartadas
- Pipeline declarativo en Terraform, no ejecucion manual por consola.
- Contrato de entrada fijo en `curated/*`.
- Separacion clara entre infraestructura estable (Terraform) y artefactos runtime (pipeline execution).
- Codigo Python versionado en repo y publicado a S3 por CI (`code_bundle_uri` inmutable por commit).
- Fase 03 usa SageMaker gestionado sin contenedor propio.
- Registro obligatorio en Model Registry antes de serving.
- `RegisterModel` condicionado por metricas y `PendingManualApproval` como gate humano.
- Alternativas descartadas:
  - jobs sueltos fuera de pipeline,
  - usar artefactos manuales como input externo de fase 03,
  - obligar ECR propio en esta fase.

## IAM usado (roles/policies/permisos clave)
- Operador humano: `data-science-user`.
- Role de ejecucion de SageMaker Pipeline (dedicado a fase 03).
- Permisos clave del role:
  - `s3:GetObject`, `s3:ListBucket` en `curated/*`,
  - `s3:GetObject` en `pipeline/code/*` para leer `CodeBundleUri`,
  - `s3:PutObject` en prefijos de artefactos del pipeline,
  - permisos de SageMaker para processing/training/evaluation/register,
  - permisos de logs en CloudWatch,
  - `iam:PassRole` acotado.

## Comandos ejecutados y resultado esperado
- Regla operativa AWS: ejecutar comandos con perfil `data-science-user`.
- `tar -czf pipeline_code.tar.gz pipeline/code/`
- `aws s3 cp pipeline_code.tar.gz s3://$DATA_BUCKET/pipeline/code/$GIT_SHA/pipeline_code.tar.gz ...`
- `terraform -chdir=terraform/03_sagemaker_pipeline fmt -check`
- `terraform -chdir=terraform/03_sagemaker_pipeline validate`
- `terraform -chdir=terraform/03_sagemaker_pipeline plan`
- `terraform -chdir=terraform/03_sagemaker_pipeline apply` (solo con plan aprobado)
- `aws sagemaker start-pipeline-execution ...` con `CodeBundleUri`, `curated/train.csv` y `curated/validation.csv`
- Resultado esperado:
  - artefacto de codigo versionado disponible en S3 por commit,
  - pipeline creado y versionado,
  - pasos `DataPreProcessing`, `TrainModel`, `ModelEvaluation` completados,
  - registro condicional en Model Registry cuando pase umbral,
  - `ModelApprovalStatus=PendingManualApproval`.

## Evidencia
Agregar:
- `terraform plan` revisado y explicado.
- URI y version de artefacto de codigo (`CodeBundleUri`) usado en la ejecucion.
- `PipelineArn` y `PipelineExecutionArn`.
- estado de cada step.
- `ModelPackageGroupName` y `ModelPackageArn` generado.
- evidencia de metricas usadas para gate.

## Criterio de cierre
- Modulo Terraform de fase 03 definido y aplicable.
- Artefacto `pipeline_code.tar.gz` publicado en S3 por commit.
- Pipeline ejecuta de punta a punta con input `curated/*`.
- Pipeline ejecuta usando `CodeBundleUri` explicito.
- Se registra una version en Model Registry cuando cumple umbral.
- Queda documentado como activar trigger programado.

## Troubleshooting especifico de codigo
1. `NoSuchKey` en `CodeBundleUri`:
   - verificar que `pipeline_code.tar.gz` existe en `s3://$DATA_BUCKET/pipeline/code/$GIT_SHA/`.
   - confirmar que el valor pasado en `start-pipeline-execution` coincide exactamente.
2. Error por ruta interna del tarball:
   - asegurar que el artefacto contiene `pipeline/code/...` y scripts esperados.
   - reconstruir el paquete con `tar -czf pipeline_code.tar.gz pipeline/code/`.
3. `AccessDenied` al leer codigo:
   - revisar policy del role de pipeline para `s3:GetObject` en `pipeline/code/*`.
   - validar tambien permisos `s3:ListBucket` en el bucket del proyecto.

## Riesgos/pendientes
- Permisos IAM insuficientes en role del pipeline (`AccessDenied` por step).
- Desacople entre definicion JSON del pipeline y variables Terraform si no se versionan juntos.
- Drift entre commit y ejecucion si no se usa `CodeBundleUri` con SHA inmutable.
- Falta de trigger programado en entorno `dev`.

## Proximo paso
Definir serving con ECS/SageMaker endpoint en `docs/tutorials/04-serving-ecs-sagemaker.md`.
