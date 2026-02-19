# Tutorial roadmap

Tutoriales por fase del proyecto Titanic SageMaker:

1. `docs/tutorials/00-foundations.md`
2. `docs/tutorials/01-data-ingestion.md`
3. `docs/tutorials/02-training-validation.md`
4. `docs/tutorials/03-sagemaker-pipeline.md`
5. `docs/tutorials/04-serving-ecs-sagemaker.md`
6. `docs/tutorials/05-cicd-github-actions.md`
7. `docs/tutorials/06-observability-operations.md`
8. `docs/tutorials/07-cost-governance.md`

## How to run this roadmap step by step
1. Completa `00-foundations.md` y valida identidad/perfil + base Terraform.
2. Ejecuta `01-data-ingestion.md` y deja `raw/train/validation` en S3.
3. Ejecuta `02-training-validation.md` como ensayo manual de puerta de calidad y documenta umbral + resultado `pass/fail`.
4. Ejecuta `03-sagemaker-pipeline.md` como flujo MLOps canonico `Processing -> Training -> Evaluation -> Register` y publicar en Model Registry.
   - separacion explicita: fase 03 arranca desde `curated/*` y resuelve preprocessing dentro del pipeline.
5. Ejecuta `04-serving-ecs-sagemaker.md` con despliegue `staging -> approval -> prod`.
6. Automatiza el flujo con `05-cicd-github-actions.md`.
7. Cierra operación con `06-observability-operations.md`.
8. Cierra gobierno de costos con `07-cost-governance.md`.

Criterio global de finalizacion:
- Existe ejecución reproducible de punta a punta.
- Hay trazabilidad desde commit hasta modelo en registry y endpoint en `prod`.
- Hay evidencia operativa y de costo registrada en `docs/iterations/`.

## Reset de estado por tutorial
Script oficial:
- `scripts/reset_tutorial_state.sh`

Modos:
1. Reset fase 02 (mantiene `raw/` y `curated/`):
   - `scripts/reset_tutorial_state.sh --target after-tutorial-2`
   - `scripts/reset_tutorial_state.sh --target after-tutorial-2 --apply --confirm RESET`
2. Reset completo del tutorial (conserva bucket e IAM):
   - `scripts/reset_tutorial_state.sh --target all`
   - `scripts/reset_tutorial_state.sh --target all --apply --confirm RESET`

Guardrails:
- `dry-run` por defecto.
- Perfil obligatorio `data-science-user`.
- Borrado real solo con `--apply --confirm RESET`.

## Verificacion de recursos activos (operacion/costo)
Script oficial:
- `scripts/check_tutorial_resources_active.sh`

Modos recomendados:
1. Revision global de recursos del roadmap:
   - `AWS_PROFILE=data-science-user scripts/check_tutorial_resources_active.sh --phase all`
2. Revision puntual por fase:
   - `AWS_PROFILE=data-science-user scripts/check_tutorial_resources_active.sh --phase 04`
   - `AWS_PROFILE=data-science-user scripts/check_tutorial_resources_active.sh --phase 07`
3. Gate para CI/smoke de gobierno:
   - `AWS_PROFILE=data-science-user scripts/check_tutorial_resources_active.sh --phase all --fail-if-active`

Salida esperada:
- Resumen por servicio con conteos `active`, `inactive`, `unknown`.
- Detalle de recursos filtrados por `project=titanic-sagemaker` o prefijo `titanic-`.
- Warnings sin abortar en caso de permisos faltantes por servicio.

## End-to-End process (Mermaid)

```mermaid
flowchart TD
  U[data-science-user] --> F0[00 Foundations]
  F0 --> D1[01 Data Ingestion<br/>Titanic raw/train/validation on S3]
  D1 --> B2[02 Training and Validation]

  subgraph MB[ModelBuild CI Pipeline]
    M0[Source Commit<br/>GitHub] --> M1[Build/Test/Package<br/>GitHub Actions]
    M1 --> M2[SageMaker Pipeline Execute]
    M2 --> M3[Processing Step<br/>Data Pre-Processing]
    M3 --> M4[Training Step<br/>Train Model]
    M4 --> M5[Processing Step<br/>Model Evaluation]
    M5 --> M6{Meets quality threshold?}
    M6 -- yes --> M7[Register Model<br/>SageMaker Model Registry]
    M6 -- no --> M8[Fail pipeline + notify]
  end

  B2 --> M0
  F0 --> C5[05 CI/CD GitHub Actions]
  C5 --> M0

  subgraph MD[ModelDeploy CD Pipeline]
    R1[Approved model package] --> S1[Deploy Staging Endpoint]
    S1 --> S2[Smoke tests]
    S2 --> G1{Manual approval}
    G1 -- approved --> P1[Deploy Prod Endpoint]
    G1 -- rejected --> RB[Rollback/hold release]
  end

  M7 --> R1
  R1 --> S1
  P1 --> S4[04 Serving ECS/SageMaker]

  E0[EventBridge Scheduler] --> SF[Step Functions + Lambda Orchestration]
  SF --> M2

  S4 --> O6[06 Observability and Operations]
  S4 --> C7[07 Cost and Governance]
  O6 --> SF
  C7 --> SF
```

Arquitectura objetivo:
- Equivalente funcional a la imagen de referencia: **ModelBuild -> Model Registry -> ModelDeploy (Staging -> Manual Approval -> Prod)**.
- En este proyecto, la implementacion recomendada usa `GitHub + GitHub Actions + Terraform` como reemplazo de `CodeCommit/CodeBuild/CodePipeline/CloudFormation`.

## Titanic dataset files (local source of truth)
- `data/titanic/raw/titanic.csv` (dataset fuente)
- `data/titanic/splits/train.csv` (dataset de entrenamiento)
- `data/titanic/splits/validation.csv` (dataset de validacion)

Iteraciones historicas:
- `docs/iterations/`

Convencion de credenciales para todos los tutoriales:
- IAM user: `data-science-user`
- Access keys logicas: `data-science-user-primary` y `data-science-user-rotation`
- Perfil AWS CLI: `data-science-user`

Regla global de ejecucion AWS:
- Toda operacion AWS del proyecto debe ejecutarse desde `data-science-user` como identidad principal.
- Para trabajo por entorno mantener el mismo perfil `data-science-user` y cambiar solo recursos/variables de entorno.
