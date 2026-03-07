# Project Mentors & Agents

Este documento define como deben trabajar los agentes de IA y mentores tecnicos en este proyecto de MLOps con AWS SageMaker usando el dataset Titanic.

La meta no es solo desplegar infraestructura o modelos. La meta es construir un pipeline end-to-end, entender cada decision y dejar evidencia para repetir el proceso sin asistencia.

## Vision del Proyecto

Construir un proyecto completo de Data Science/MLOps con:

- Infraestructura durable gobernada por `config/project-manifest.json` y scripts idempotentes versionados, sin depender de `terraform plan/apply/output` para ejecutar las fases 00-07.
- Artefactos de runtime gestionados via SageMaker SDK V3: processing jobs, training jobs, pipeline executions, model packages y endpoints.
- Operador IAM humano `data-science-user` para operaciones manuales e interactivas del tutorial.
- CI/CD desde GitHub (GitHub Actions) obligatorio, usando un rol OIDC dedicado para el runner.
- Entrenamiento y validacion en SageMaker.
- Registro y promocion de modelos antes del update de endpoint.
- Orquestacion ML build via SageMaker Pipelines. Step Functions/Lambda/EventBridge Scheduler reservados para deploy y tareas auxiliares.
- Observabilidad con CloudWatch.
- Control de costos y gobierno desde el inicio.
- Metodologia SDK V3 notebook-first para fases de desarrollo y exploracion.
- Ruta canonica de ejecucion para el equipo DS: `docs/tutorials/` + `docs/aws/policies/`.

## Objetivos de Aprendizaje

Al finalizar, el ingeniero debe poder:

1. Explicar por que existe cada servicio en la arquitectura.
2. Diseñar IAM least-privilege por modulo sin depender de permisos admin.
3. Ejecutar un flujo CI/CD reproducible para cambios de codigo e infraestructura.
4. Operar y debuggear training jobs/endpoints con logs y metricas.
5. Iterar con documentacion clara en `docs/`.

## Alcance Arquitectonico

Servicios esperados y su rol minimo:

- `S3`: datasets, artefactos, paquetes de pipeline, outputs.
- `ECR`: imagenes de entrenamiento/inferencia (custom containers cuando aplique).
- `SageMaker`: processing, training, model registry, pipeline (orquestacion ML build), endpoint.
- `Step Functions`: orquestacion de deploy y flujos auxiliares (no usado para ML build, que usa SageMaker Pipelines).
- `Lambda`: tareas de glue/logica corta, validaciones, triggers, cost governance.
- `EventBridge` + `Scheduler`: ejecucion programada, disparadores, apagado de recursos no-prod.
- `CloudWatch`: logs, metricas, alarmas, dashboards.
- `EC2`: solo si existe necesidad explicita (evitar por defecto).
- `ECS/Fargate`: opcional, solo si se necesita ETL o integracion de servicio que no cubra SageMaker Processing. No se usa actualmente.
- `Cost Management`: presupuestos, alarmas y etiquetado obligatorio.

## Contrato de Colaboracion con Agentes

Toda respuesta tecnica del agente debe incluir:

1. `Goal`: que se intenta lograr.
2. `Change`: que se modificara o ejecutara.
3. `Why`: razon tecnica y tradeoff.
4. `Validation`: como se comprobara.
5. `Docs to update`: que archivo(s) en `docs/` deben registrar la decision.

Si hay error o incidente, el agente debe reportar:

1. Causa raiz.
2. Evidencia (log/comando/sintoma).
3. Correccion aplicada o recomendada.
4. Control preventivo para no repetirlo.

## Regla Global para Agentes LLM (AWS Identity)

Toda operacion AWS manual o interactiva ejecutada por agentes LLM en este proyecto debe usar:
- Identidad base: `data-science-user`
- Perfil operativo unico: `data-science-user`

Excepcion permitida:
- GitHub Actions debe usar un rol OIDC dedicado del proyecto; no debe reutilizar access keys de `data-science-user`.

Prohibido:
- Usar root account para operaciones del proyecto.
- Usar otros usuarios IAM humanos distintos de `data-science-user`.
- Usar access keys estaticas de usuarios humanos dentro de CI/CD.

## Roles de Mentoria

### 1. Arquitecto de Plataforma (AWS / Bootstrap Operativo)

- Mision: traducir la arquitectura AWS a un manifest versionado, scripts idempotentes y contratos claros de entorno.
- Foco: `config/project-manifest.json`, `scripts/resolve_project_env.py`, `scripts/ensure_project_bootstrap.py`, `scripts/ensure_github_actions_role.py`, naming, tags y outputs operativos.
- Regla: no ejecutar `--apply` sin validacion previa en modo `--check`, diff entendido y evidencia en `docs/`.

### 2. Especialista en MLOps (SageMaker/CI-CD)

- Mision: asegurar pipeline de entrenamiento, registro y despliegue.
- Foco: Model Registry, promotion gates, rollback y reproducibilidad.
- Regla: nunca actualizar endpoint sin pasar por validacion y registro.

### 3. Debugger Educativo

- Mision: resolver incidentes explicando la causa raiz.
- Foco: CloudWatch logs, estados de SageMaker Pipelines/Step Functions, errores IAM.
- Regla: cada fix deja aprendizaje operativo en docs.

### 4. Guardian de Seguridad y Costos

- Mision: minimizar riesgo por permisos excesivos y gasto no controlado.
- Foco: least-privilege, tagging, budgets, alarmas, scheduler.
- Regla: cualquier wildcard en IAM requiere justificacion documentada.

## Flujo por Fases (Documentacion Obligatoria)

Toda iteracion debe mapearse a una fase y tener evidencia en `docs/`.

Archivos base esperados:

- `docs/tutorials/00-foundations.md`
- `docs/tutorials/01-data-ingestion.md`
- `docs/tutorials/02-training-validation.md`
- `docs/tutorials/03-sagemaker-pipeline.md`
- `docs/tutorials/04-serving-sagemaker.md`
- `docs/tutorials/05-cicd-github-actions.md`
- `docs/tutorials/06-observability-operations.md`
- `docs/tutorials/07-cost-governance.md`
- `docs/iterations/ITER-YYYYMMDD-XX.md`

Contenido minimo por archivo:

1. Objetivo y contexto.
2. Decisiones tecnicas y alternativas descartadas.
3. IAM usado (roles/policies/permisos clave).
4. Comandos ejecutados y resultado esperado.
5. Evidencia (outputs, logs, metricas, capturas si aplica).
6. Riesgos/pendientes.
7. Proximo paso.

## Estandares de Infraestructura Operativa

El camino operativo del proyecto ya no depende de Terraform. La fuente de verdad para nombres,
tags y recursos duraderos es:

- `config/project-manifest.json`
- `scripts/resolve_project_env.py`
- `scripts/ensure_project_bootstrap.py`
- `scripts/ensure_github_actions_role.py`
- `scripts/publish_pipeline_code.sh`
- `scripts/upsert_pipeline.py`

Contrato actual del proyecto:

- `config/project-manifest.json` define cuenta, region, bucket, roles, pipeline, endpoints y tags.
- `scripts/resolve_project_env.py` emite el entorno compartido por local y CI.
- `scripts/ensure_project_bootstrap.py` converge bucket, SageMaker execution role, pipeline role y Model Package Group.
- `scripts/ensure_github_actions_role.py` converge el rol OIDC del runner si el provider ya existe.
- `scripts/publish_pipeline_code.sh` publica `pipeline/code/` y scripts auxiliares en S3.
- `scripts/upsert_pipeline.py` construye y publica la definicion del pipeline con SageMaker SDK V3.

Regla: `docs/tutorials/00-07` deben seguir siendo ejecutables sin `terraform plan/apply/output`.

Antes de ejecutar cualquier `--apply`, el agente debe validar:

1. Convenciones de nombre y tags del `project-manifest`.
2. Modo `--check` del script correspondiente.
3. Reglas IAM least-privilege.
4. Impacto en costo estimado.
5. Evidencia y decision registradas en `docs/`.

Terraform puede seguir existiendo en `terraform/` como referencia historica o trabajo futuro,
pero no debe reintroducirse como dependencia operativa del roadmap actual sin actualizar
primero `docs/tutorials/` y `docs/aws/policies/`.

Tags obligatorios en todos los recursos soportados:

- `project = "titanic-sagemaker"`
- `env = "<dev|prod>"`
- `owner = "<team-or-user>"`
- `managed_by = "scripts"`
- `cost_center = "<value>"`

## Estandares CI/CD (GitHub Actions)

CI/CD obligatorio y versionado desde GitHub.

Estrategia de ambientes:

- `dev`: despliegue automatico desde rama principal tras checks.
- `prod`: despliegue con gate de aprobacion.

Flujo minimo:

1. Pull Request:
   - lint/test/build (codigo)
   - validar `config/project-manifest.json` y scripts operativos en modo `--check`
   - security checks (dependencias, IAM y supply chain)
2. Merge a main:
   - asumir rol OIDC dedicado del runner
   - asegurar recursos duraderos requeridos por el tutorial
   - publicar codigo del pipeline, hacer `upsert` y ejecutar el flujo en `dev`
   - smoke tests de pipeline/modelo/endpoint
3. Promocion a `prod`:
   - aprobacion manual + evidencia de `dev`
   - aprobar `ModelPackageArn` y desplegar `prod`

Reglas de modelo:

1. Entrenar y validar.
2. Registrar modelo.
3. Evaluar criterio de promocion.
4. Actualizar endpoint solo si pasa umbral.

Seguridad CI/CD:

- GitHub Actions pinned por SHA (no por tag) para mitigar supply-chain attacks.
- Secretos solo via GitHub Secrets o OIDC; nunca static keys en workflows.
- Considerar herramientas como `gitleaks`, `checkov`, o `trivy` en el flujo PR.
- El workflow no debe depender de `terraform plan/apply/output`.

## Modelo IAM para Usuario de Data Science

Principio: separar identidad humana de roles de ejecucion.

### Usuario operador DS

- Permisos minimos para:
  - ejecutar workflows CI/CD
  - leer logs/metricas
  - consultar estado de recursos
  - asumir roles acotados por entorno

### Credenciales estandar del operador DS

- IAM User oficial: `data-science-user`
- Nombres logicos de access keys:
  - `data-science-user-primary` (activa)
  - `data-science-user-rotation` (reserva para rotacion)
- Perfiles AWS CLI oficiales:
  - `data-science-user`

Reglas obligatorias:
1. Nunca commitear `AccessKeyId` o `SecretAccessKey` reales.
2. Operar todas las acciones AWS manuales/locales con el perfil `data-science-user`.
3. Mantener maximo 2 access keys por usuario y documentar la rotacion en `docs/iterations/`.
4. Los workflows de GitHub Actions deben usar un rol OIDC dedicado; no deben emularse con las keys del usuario DS.

### Roles de workload (servicios)

Definir roles separados para:

- SageMaker execution role
- SageMaker Pipeline execution role (si difiere del execution role base)
- GitHub Actions OIDC deployer role
- Lambda role (cuando se implemente cost governance)
- Step Functions role (cuando se implemente orquestacion de deploy)
- EventBridge/Scheduler invocations

Controles obligatorios:

1. `iam:PassRole` limitado a roles especificos y servicios esperados.
2. Evitar `Action: "*"`, `Resource: "*"`.
3. Secretos via servicios dedicados (no hardcode).
4. Politicas separadas por modulo y entorno.

### Politica de teardown

El operador `data-science-user` necesita permisos adicionales para limpiar recursos no-prod y
recursos duraderos creados por los scripts del tutorial:
- `sagemaker:DeleteModelPackage`, `sagemaker:DeleteModelPackageGroup`
- `s3:DeleteBucketPolicy`, `s3:ListBucketVersions`, `s3:DeleteObject` (versioned)
- `iam:ListInstanceProfilesForRole`, `iam:DeleteRolePolicy`, `iam:DeleteRole`

Estos permisos deben otorgarse en una politica separada (`ds-teardown-policy.json`) y pueden
restringirse a entornos no-prod.

## Observabilidad y Operacion

Obligatorio configurar:

1. CloudWatch Logs para training, pipelines y lambdas.
2. Metricas de exito/fallo y tiempos por etapa.
3. Alarmas para errores de entrenamiento, fallos de endpoint y costos.
4. Runbook breve por incidente recurrente.

Checklist operativo minimo por release:

1. Pipeline ejecuto sin errores.
2. Endpoint responde smoke test.
3. Alarmas en estado saludable.
4. Costos dentro de umbral esperado.

## Gobierno de Costos

Reglas minimas:

1. Presupuesto mensual con alertas.
2. Programar apagado/suspension en no-produccion cuando sea posible.
3. Revisar recursos huérfanos por iteracion.
4. Bloquear cambios sin tags obligatorios.

## Definition of Done (DoD)

Una tarea se considera completa cuando:

1. Cambio tecnico implementado y validado.
2. Evidencia registrada en docs de fase e iteracion.
3. Riesgo/rollback identificado.
4. Aprendizaje clave explicado en lenguaje claro.
5. Si aplica, CI/CD e IAM actualizados coherentemente.

## Criterios de Exito del Proyecto

1. Existe pipeline end-to-end reproducible para Titanic.
2. El flujo desde GitHub hasta SageMaker esta automatizado.
3. Se puede promover de `dev` a `prod` con controles.
4. El operador DS entiende y puede explicar arquitectura, IAM y CI/CD.
5. El proyecto mantiene trazabilidad tecnica en `docs/`.
