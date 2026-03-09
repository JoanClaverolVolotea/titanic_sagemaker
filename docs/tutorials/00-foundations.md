# 00 Foundations

## Objetivo y contexto
Alinear el proyecto con el SageMaker Python SDK V3 vendoreado localmente. Esta fase cubre
el entorno Python, la sesion base de SageMaker, los imports canonicos de V3 y las
convenciones del repositorio.

Esta fase valida el entorno Python, el manifest versionado del proyecto y el bootstrap
minimo de recursos duraderos que las fases 01-05 necesitan para operar sin Terraform.

## Resultado minimo esperado
1. `sagemaker` 3.x instalado en el entorno activo.
2. Imports base de V3 verificados: `Session`, `ModelTrainer`, `ModelBuilder`, `Pipeline`.
3. Perfil operativo `data-science-user` exportado para los ejemplos locales.
4. `scripts/ensure_project_bootstrap.py` validado localmente en modo `--check`.
5. Queda explicito como resolver o converger `SAGEMAKER_EXECUTION_ROLE_ARN` para las
   fases 02-04.

## Fuentes locales alineadas con SDK V3
1. `vendor/sagemaker-python-sdk/docs/index.rst`
2. `vendor/sagemaker-python-sdk/docs/installation.rst`
3. `vendor/sagemaker-python-sdk/docs/overview.rst`
4. `vendor/sagemaker-python-sdk/docs/quickstart.rst`
5. `vendor/sagemaker-python-sdk/docs/training/index.rst`
6. `vendor/sagemaker-python-sdk/docs/inference/index.rst`
7. `vendor/sagemaker-python-sdk/docs/ml_ops/index.rst`
8. `vendor/sagemaker-python-sdk/migration.md`

## Prerequisitos concretos
1. Python 3.9+ instalado.
2. Haber completado `docs/aws/policies/README.md` para bootstrapear y validar
   `data-science-user`.
3. Perfil AWS CLI `data-science-user` configurado para el proyecto.
4. `boto3` disponible para ejecutar los scripts de bootstrap.
5. Ejecutar este tutorial desde la raiz del repositorio.

## Estructura relevante del repositorio
```text
titanic_sagemaker/
  data/titanic/           # Dataset Titanic local del proyecto
  docs/tutorials/         # Roadmap V3
  pipeline/code/          # Scripts usados por Processing/Evaluation
  config/                 # Manifest versionado del proyecto
  scripts/                # Scripts operativos locales
  vendor/                 # Documentacion vendoreada del SDK
```

## Paso a paso (ejecucion)

### 1. Exportar el contexto operativo del proyecto

```bash
eval "$(python3 scripts/resolve_project_env.py --emit-exports)"
```

### 2. Instalar SageMaker SDK V3 como paquete principal

La guia de instalacion local usa `pip install sagemaker` como entrada canonica. El paquete
principal agrega la experiencia V3 completa.

```bash
pip install sagemaker
# o con uv:
uv pip install sagemaker
```

### 3. Verificar version e imports V3

```python
from importlib.metadata import version

from sagemaker.core.helper.session_helper import Session, get_execution_role
from sagemaker.train import ModelTrainer
from sagemaker.serve.model_builder import ModelBuilder
from sagemaker.mlops.workflow.pipeline import Pipeline

sm_version = version("sagemaker")
assert sm_version.split(".")[0] == "3", f"Se requiere SageMaker SDK V3, encontrado {sm_version}"

session = Session()
print(f"sagemaker={sm_version}")
print(f"Region: {session.boto_region_name}")
try:
    print(f"SageMaker default bucket: {session.default_bucket()}")
except Exception as exc:
    print(f"SageMaker default bucket no disponible con el IAM actual: {exc}")
print("Imports V3 verificados: Session, ModelTrainer, ModelBuilder, Pipeline")
```

### 4. Resolver el execution role de SageMaker

La documentacion local de quickstart usa `get_execution_role()` dentro de runtimes
administrados por SageMaker. Fuera de ese entorno debes aportar el ARN manualmente.

```python
import os

from sagemaker.core.helper.session_helper import get_execution_role

try:
    sagemaker_execution_role_arn = get_execution_role()
except Exception:
    sagemaker_execution_role_arn = os.environ.get("SAGEMAKER_EXECUTION_ROLE_ARN", "")

print(f"SAGEMAKER_EXECUTION_ROLE_ARN={sagemaker_execution_role_arn or '<pendiente>'}")
```

Regla para este roadmap:
- Si ejecutas localmente fuera de SageMaker Studio/notebook, exporta
  `SAGEMAKER_EXECUTION_ROLE_ARN` antes de las fases 02-04.
- Si ejecutas dentro de un runtime administrado, `get_execution_role()` es el patron V3
  preferido segun `quickstart.rst`.

### 5. Validar foundations sin Terraform

```bash
python3 scripts/ensure_project_bootstrap.py --check
# Si necesitas converger bucket, roles y registry:
# python3 scripts/ensure_project_bootstrap.py --apply
```

Notas operativas:
- `--check` ya inspecciona bucket, roles IAM y `Model Package Group`.
- Para usar `--check` o `--apply`, el operador necesita `DataScienceTutorialBootstrap`.

### 6. Fijar el mapa V3 del proyecto

Patrones canonicos del roadmap, alineados con la documentacion local:

| Capacidad | Patron V3 del proyecto |
|---|---|
| Sesion | `sagemaker.core.helper.session_helper.Session` |
| Training manual | `sagemaker.train.ModelTrainer` |
| Serving | `sagemaker.serve.model_builder.ModelBuilder` |
| Pipeline MLOps | `PipelineSession` + `ProcessingStep` + `TrainingStep` + `ModelStep` |
| Registro | `ModelBuilder.register(...)` |
| Invocacion | `endpoint.invoke(...)` |

Reglas que se consideran fuera del estandar V3 de este roadmap:
- `Estimator` / `Predictor` de V2 como interfaz principal.
- Guias que dependen de imports legacy `sagemaker.workflow.*` cuando existe el namespace V3
  `sagemaker.mlops.workflow.*`.
- Describir la arquitectura a partir de templates JSON como fuente de verdad primaria en vez
  de una definicion Python con clases V3.

## Decisiones tecnicas y alternativas descartadas
- Se usa `pip install sagemaker` como instalacion canonica, tal como define
  `installation.rst`.
- `ModelTrainer` reemplaza a estimators framework-specific como patron de training.
- `ModelBuilder` reemplaza a clases de despliegue V2 como patron de serving.
- `Pipeline`, `ProcessingStep`, `TrainingStep` y `ModelStep` son la referencia del roadmap
  para MLOps V3.
- Se descartan ejemplos V2 como fuente primaria del tutorial.

## IAM usado (roles/policies/permisos clave)
- Perfil operativo del proyecto: `data-science-user`.
- `scripts/ensure_project_bootstrap.py --check` y `--apply` requieren
  `DataScienceTutorialBootstrap` porque validan o crean bucket, roles IAM y el
  `Model Package Group`.
- Para las fases 01-06, el bundle operativo pasa a ser `DataScienceTutorialOperator`.
- Las fases 02-04 requieren un `SAGEMAKER_EXECUTION_ROLE_ARN` valido.
- Este archivo ya no depende de Terraform; el bucket y los roles pueden convergerse con
  `scripts/ensure_project_bootstrap.py`.
- `session.default_bucket()` es informativo y puede resolver el bucket por defecto de
  SageMaker, que es distinto del bucket gobernado por `config/project-manifest.json`.

## Evidencia
Agregar:
- Version instalada de `sagemaker`.
- Salida del snippet de imports y `Session()`.
- Salida de `scripts/ensure_project_bootstrap.py --check`.
- Valor resuelto para `SAGEMAKER_EXECUTION_ROLE_ARN` o nota de que se resolvera en runtime
  administrado.

## Criterio de cierre
- `sagemaker` 3.x instalado y verificado.
- `Session()` funcional con el perfil operativo del proyecto.
- Imports V3 canonicos verificados.
- `scripts/ensure_project_bootstrap.py` validado localmente.
- Queda claro como se resolvera el execution role para las fases runtime.

## Riesgos/pendientes
- Si no existe `SAGEMAKER_EXECUTION_ROLE_ARN`, las fases 02-04 no son ejecutables localmente.
- El manifest no es la fuente de verdad para recursos runtime de SageMaker; esos recursos
  siguen siendo artefactos del SDK.
- Cualquier uso de APIs V2 debe tratarse como desviacion del roadmap.

## Proximo paso
Cargar el dataset local del proyecto en S3 usando `docs/tutorials/01-data-ingestion.md`.
