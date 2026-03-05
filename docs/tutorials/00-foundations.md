# 00 Foundations

## Objetivo y contexto
Definir la base completa del proyecto: cuenta AWS, identidad operativa, backend de Terraform
state, convenciones de naming/tagging, estrategia de ambientes (`dev` y `prod`), entorno
Python con SageMaker SDK V3, y reglas de colaboracion.

Al terminar esta fase tienes todo lo necesario para ejecutar las fases 01-07 sin ambiguedades.

## Resultado minimo esperado
1. Identidad operativa validada con `data-science-user`.
2. Entorno Python con `sagemaker>=3.5.0` instalado y verificado.
3. Estandar de tags obligatorios definido para todos los recursos Terraform.
4. Flujo base de `terraform fmt/validate/plan` ejecutable.
5. Arquitectura objetivo de fases `01..07` aprobada y trazable.

## Fuentes oficiales usadas en esta fase
1. `https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html`
2. `https://docs.aws.amazon.com/STS/latest/APIReference/API_GetCallerIdentity.html`
3. `https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html`
4. `https://docs.aws.amazon.com/tag-editor/latest/userguide/best-practices-and-strats.html`
5. `https://registry.terraform.io/providers/hashicorp/aws/latest/docs#default_tags`
6. SageMaker SDK V3 docs: `vendor/sagemaker-python-sdk/docs/index.rst`
7. SageMaker SDK V3 installation: `vendor/sagemaker-python-sdk/docs/installation.rst`

## Prerequisitos concretos
1. Python 3.9+ instalado (`python3 --version`).
2. AWS CLI v2 instalado y configurado (`aws --version`).
3. Terraform >= 1.5 instalado (`terraform -version`).
4. Perfil AWS CLI `data-science-user` configurado en `~/.aws/credentials`.
5. Gestor de paquetes `uv` o `pip` disponible.
6. Ejecutar este tutorial desde la raiz del repositorio.

## Estructura del repositorio
```
titanic_sagemaker/
  data/titanic/           # Dataset Titanic (raw + splits)
  docs/tutorials/         # Estos tutoriales (fases 00-07)
  docs/iterations/        # Evidencia por iteracion
  docs/aws/policies/      # Politicas IAM del proyecto
  pipeline/code/          # Scripts de pipeline SageMaker (preprocess, evaluate, train)
  scripts/                # Scripts operativos (splits, reset, check, IAM)
  terraform/              # IaC por fase (00_foundations, 03_sagemaker_pipeline, ...)
  vendor/                 # SDK vendoreado (gitignored, solo local)
  .github/workflows/      # CI/CD workflows
```

## Paso a paso (ejecucion)

### 1. Confirmar identidad operativa

```bash
aws sts get-caller-identity --profile data-science-user
```

Resultado esperado: JSON con `Account`, `UserId` y `Arn` del usuario `data-science-user`.

### 2. Instalar y verificar SageMaker SDK V3

El SDK V3 se compone de cuatro paquetes independientes que se instalan juntos:

| Paquete | Proposito |
|---|---|
| `sagemaker-core` | Session, resources, shapes, image_uris, workflow primitives |
| `sagemaker-train` | ModelTrainer, configs, distributed training |
| `sagemaker-serve` | ModelBuilder, InferenceSpec, SchemaBuilder |
| `sagemaker-mlops` | Pipeline, Steps, ConditionStep, ModelStep |

Instalacion:

```bash
pip install "sagemaker>=3.5.0"
# o con uv:
uv pip install "sagemaker>=3.5.0"
```

Verificacion:

```bash
python3 -c "
from importlib.metadata import version
v = version('sagemaker')
print(f'sagemaker={v}')
assert v.split('.')[0] == '3', f'Se requiere V3, encontrado {v}'
print('OK: SageMaker SDK V3 instalado correctamente')
"
```

Verificacion de subpaquetes:

```python
from sagemaker.core.helper.session_helper import Session      # core
from sagemaker.train import ModelTrainer                       # train
from sagemaker.serve.model_builder import ModelBuilder         # serve
from sagemaker.mlops.workflow.pipeline import Pipeline         # mlops
print("Todos los subpaquetes V3 importan correctamente")
```

Documentacion de referencia local:
- `vendor/sagemaker-python-sdk/docs/installation.rst`
- `vendor/sagemaker-python-sdk/docs/overview.rst`
- `vendor/sagemaker-python-sdk/migration.md` (guia de migracion V2 -> V3)

### 3. Definir convenciones globales

Tags obligatorios en todos los recursos Terraform:

| Tag | Valor |
|---|---|
| `project` | `titanic-sagemaker` |
| `env` | `dev` o `prod` |
| `owner` | `data-science-user` |
| `managed_by` | `terraform` |
| `cost_center` | `data-science` |

Naming de recursos: prefijo `titanic-` para todos los recursos del proyecto.

Separacion de ambientes: `dev` y `prod` como sufijo o variable de entorno.

### 4. Configurar provider Terraform con tags obligatorios

Plantilla para todos los modulos Terraform del proyecto:

```hcl
provider "aws" {
  region  = var.aws_region
  profile = "data-science-user"
  default_tags {
    tags = {
      project     = "titanic-sagemaker"
      env         = var.environment
      owner       = var.owner
      managed_by  = "terraform"
      cost_center = var.cost_center
    }
  }
}
```

### 5. Validar base Terraform del modulo de foundations

```bash
terraform -chdir=terraform/00_foundations fmt -check
terraform -chdir=terraform/00_foundations validate
terraform -chdir=terraform/00_foundations plan
```

Resultado esperado: plan limpio con recursos etiquetados segun convenciones.

### 6. Aprobar arquitectura objetivo

El proyecto implementa dos flujos principales:

**ModelBuild CI** (fases 02-03):
```
DataPreProcessing -> TrainModel -> ModelEvaluation -> QualityGate -> RegisterModel
```

**ModelDeploy CD** (fase 04):
```
Approve ModelPackage -> Deploy staging -> Smoke test -> Approve -> Deploy prod
```

Clases V3 involucradas en cada flujo:

| Flujo | Clases V3 principales |
|---|---|
| Processing | `sagemaker.core.processing.ScriptProcessor` |
| Training | `sagemaker.train.ModelTrainer` con `Compute`, `InputData` |
| Pipeline | `sagemaker.mlops.workflow.Pipeline` con `TrainingStep`, `ProcessingStep`, `ModelStep`, `ConditionStep` |
| Model Registry | `sagemaker.core.resources.ModelPackage`, `ModelPackageGroup` |
| Serving | `sagemaker.serve.ModelBuilder` -> `build()` -> `deploy()` |
| Inference | `sagemaker.core.resources.Endpoint.invoke()` |

## Decisiones tecnicas y alternativas descartadas
- IaC estandar: Terraform.
- CI/CD estandar: GitHub Actions.
- Ambientes: `dev` y `prod`.
- SDK: SageMaker Python SDK V3 (>= 3.5.0). V2 descartado por deprecacion.
- Cost tracking obligatorio desde foundations con `default_tags` + tags por recurso.
- Arquitectura objetivo: ModelBuild CI + ModelDeploy CD.
- Pipeline definition: SDK-driven (V3 Python). Terraform-managed JSON template como alternativa legacy.
- Alternativas descartadas: despliegues manuales sin pipeline, V2 Estimator/Predictor patterns.

## IAM usado (roles/policies/permisos clave)
- Usuario operador DS con permisos minimos para ejecutar pipelines y leer observabilidad.
- Usuario IAM oficial: `data-science-user`.
- Access keys logicas: `data-science-user-primary` (activa) y `data-science-user-rotation` (reserva).
- Perfil AWS CLI oficial: `data-science-user`.
- Roles de ejecucion por servicio (SageMaker, Lambda, Step Functions).
- `iam:PassRole` restringido a roles esperados.
- Politicas IAM documentadas en `docs/aws/policies/`.

## Entregable minimo de esta fase
- Checklist de arquitectura aprobado con estos bloques:
  - SageMaker Pipeline con pasos de `Processing -> Training -> Evaluation -> Register`.
  - Model Registry obligatorio antes de cualquier deployment.
  - Pipeline de despliegue con endpoint `staging`, gate manual y despliegue a `prod`.
  - SDK V3 instalado y verificado.

## Criterio de cierre
- Identidad y perfil AWS validados.
- SageMaker SDK V3 instalado y subpaquetes verificados.
- Convenciones y tags documentados.
- `terraform plan` revisado sin sorpresas.
- Arquitectura objetivo aprobada y trazada a fases `01..07`.

## Evidencia
Agregar aqui:
- Salida de `aws sts get-caller-identity`.
- Version de SDK instalada (`sagemaker==3.x.x`).
- Salida de `terraform plan` de foundations.
- Decisiones de backend state y convenciones aprobadas.

## Riesgos/pendientes
- Definir limites iniciales de costos.
- Validar permisos exactos para cada modulo.
- Mantener SDK actualizado ante cambios menores de V3.

## Proximo paso
Avanzar a ingestion y gobierno de datos en `docs/tutorials/01-data-ingestion.md`.
