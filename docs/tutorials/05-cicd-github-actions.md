# 05 CI/CD GitHub Actions

## Objetivo y contexto
Definir e implementar automatizacion CI/CD para:
1. Ejecutar `ModelBuild` (calidad + pipeline + registro).
2. Ejecutar `ModelDeploy` (staging -> smoke -> approval -> prod).

Estado actual de fase 05:
- No implementada de punta a punta en este repositorio.
- Esta guia define backlog ejecutable con gates de aceptacion para cerrar fase.

## Resultado minimo esperado
1. Existe workflow `model-build.yml` en estado operativo.
2. Existe workflow `model-deploy.yml` en estado operativo.
3. `main` dispara `ModelBuild` automaticamente.
4. `ModelDeploy` promueve a `prod` solo con aprobacion manual.
5. Artefactos CI/CD incluyen `PipelineExecutionArn`, `ModelPackageArn`, `EndpointArn`.

## Fuentes oficiales (AWS/GitHub) usadas en esta fase
1. `https://docs.aws.amazon.com/sagemaker/latest/APIReference/API_StartPipelineExecution.html`
2. `https://docs.aws.amazon.com/sagemaker/latest/APIReference/API_DescribePipelineExecution.html`
3. `https://docs.aws.amazon.com/sagemaker/latest/APIReference/API_ListPipelineExecutionSteps.html`
4. `https://docs.aws.amazon.com/sagemaker/latest/APIReference/API_ListModelPackages.html`
5. `https://docs.aws.amazon.com/sagemaker/latest/APIReference/API_DescribeModelPackage.html`
6. `https://docs.aws.amazon.com/sagemaker/latest/APIReference/API_CreateModel.html`
7. `https://docs.aws.amazon.com/sagemaker/latest/APIReference/API_CreateEndpointConfig.html`
8. `https://docs.aws.amazon.com/sagemaker/latest/APIReference/API_CreateEndpoint.html`
9. `https://docs.aws.amazon.com/sagemaker/latest/APIReference/API_UpdateEndpoint.html`
10. `https://docs.aws.amazon.com/sagemaker/latest/APIReference/API_InvokeEndpoint.html`
11. `https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html`
12. `https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithWebIdentity.html`
13. `https://docs.github.com/actions/using-workflows/workflow-syntax-for-github-actions`
14. `https://docs.github.com/actions/deployment/targeting-different-environments/using-environments-for-deployment`
15. Referencia local de estudio: `docs/aws/sagemaker-dg.pdf`.

## Alcance de implementacion (backlog con estado)
### Workflow `model-build.yml` (planned)
Objetivo:
1. Ejecutar checks de PR y build de modelo en `main`.

Estado:
- `planned` (no cerrado).

Bloques minimos:
1. `lint/test/security`.
2. `terraform fmt -check`, `terraform validate`, `terraform plan`.
3. Trigger de SageMaker Pipeline fase 03.
4. Espera de estado terminal (`Succeeded` o `Failed`).
5. Publicacion de artefactos: `PipelineExecutionArn`, estado por step, `ModelPackageArn` reciente.

### Workflow `model-deploy.yml` (planned)
Objetivo:
1. Promocionar modelo aprobado a `staging` y luego a `prod` con gate.

Estado:
- `planned` (no cerrado).

Bloques minimos:
1. Seleccion de `ModelPackageArn` aprobado.
2. Deploy `staging`.
3. Smoke test de inferencia.
4. Aprobacion manual (`GitHub Environment: prod`).
5. Deploy `prod`.
6. Publicacion de artefactos: endpoints y evidencia de smoke.

## Decisiones tecnicas y alternativas descartadas
1. Mantener dos workflows separados (`ModelBuild` y `ModelDeploy`) para desacoplar riesgo.
2. OIDC recomendado para GitHub Actions (evitar access keys estaticas en CI).
3. `ModelRegistry` es contrato obligatorio entre build y deploy.
4. Descartado: deploy directo a `prod` sin `staging` ni aprobacion manual.
5. Descartado: mezcla de build/deploy en un solo workflow sin gates.

## Criterios de aceptacion de fase 05
1. PR checks operativos: `fmt/validate/plan/tests/security`.
2. `main` dispara `ModelBuild` y deja `ModelPackageArn` trazable.
3. `ModelDeploy` ejecuta `staging -> smoke -> approval -> prod`.
4. Artifacts de workflow incluyen `PipelineExecutionArn`, `ModelPackageArn`, evidencia de endpoints.

## IAM usado (roles/policies/permisos clave)
1. Identidad base del proyecto: `data-science-user`.
2. En CI/CD usar role asumible por OIDC (least privilege por entorno).
3. `iam:PassRole` restringido a roles esperados de SageMaker hosting/pipeline.
4. Permisos minimos:
   - SageMaker pipeline execution/read,
   - model registry read/update approval,
   - endpoint create/update/describe/invoke,
   - lectura de logs para evidencia.

## Comandos ejecutados y resultado esperado
Comandos de verificacion local (pre-implementacion):

```bash
# Validar sintaxis de workflow cuando se creen los archivos
# (usar actionlint si esta disponible en el entorno)
actionlint

# Verificar que existe el checker operativo de recursos
AWS_PROFILE=data-science-user scripts/check_tutorial_resources_active.sh --phase all
```

Resultado esperado:
1. Workflows sin errores de sintaxis.
2. Artefactos y evidencias definidos antes de merge.
3. Gate manual visible para entorno `prod`.

## Evidencia requerida
1. Link al run de `model-build.yml` exitoso en `main`.
2. Link al run de `model-deploy.yml` con evidencia de aprobación manual.
3. `PipelineExecutionArn` y estado por step.
4. `ModelPackageArn` promovido.
5. `EndpointArn` de `staging` y `prod`.

## Criterio de cierre
1. `model-build.yml` operativo en PR y `main`.
2. `model-deploy.yml` operativo con gate manual en `prod`.
3. Trazabilidad completa commit -> pipeline -> model package -> endpoint.
4. Fase deja evidencia reproducible en `docs/iterations/`.

## Riesgos/pendientes
1. OIDC mal configurado (assume role falla en runtime).
2. Permisos excesivos por no segmentar roles dev/prod.
3. Promocion bloqueada si falta criterio estandar de smoke.

## Proximo paso
Aterrizar `docs/tutorials/06-observability-operations.md` para monitoreo, alarmas y runbooks asociados a deploy/pipeline.
