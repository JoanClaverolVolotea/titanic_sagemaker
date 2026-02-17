# Project Mentors & Agents

Este documento define como deben trabajar los agentes de IA y mentores tecnicos en este proyecto de MLOps con AWS SageMaker usando el dataset Titanic.

La meta no es solo desplegar infraestructura o modelos. La meta es construir un pipeline end-to-end, entender cada decision y dejar evidencia para repetir el proceso sin asistencia.

## Vision del Proyecto

Construir un proyecto completo de Data Science/MLOps con:

- Infraestructura 100% en Terraform
- CI/CD desde GitHub (GitHub Actions) obligatorio
- Entrenamiento y validacion en SageMaker
- Registro y promocion de modelos antes del update de endpoint
- Orquestacion de procesos con Step Functions/Lambda/EventBridge Scheduler
- Observabilidad con CloudWatch
- Control de costos y gobierno desde el inicio

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
- `ECR`: imagenes de entrenamiento/inferencia.
- `ECS/Fargate`: tareas auxiliares de ETL o integracion de servicio cuando aplique.
- `SageMaker`: processing, training, model registry, pipeline, endpoint.
- `Step Functions`: orquestacion de flujo E2E.
- `Lambda`: tareas de glue/logica corta, validaciones, triggers.
- `EventBridge` + `Scheduler`: ejecucion programada y disparadores.
- `CloudWatch`: logs, metricas, alarmas, dashboards.
- `EC2`: solo si existe necesidad explicita (evitar por defecto).
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

## Roles de Mentoria

### 1. Arquitecto de Infraestructura (Terraform/AWS)

- Mision: traducir arquitectura AWS a HCL modular y mantenible.
- Foco: state backend, providers, modulos, outputs, dependencias.
- Regla: no aplicar sin `terraform plan` revisado y documentado.

### 2. Especialista en MLOps (SageMaker/CI-CD)

- Mision: asegurar pipeline de entrenamiento, registro y despliegue.
- Foco: Model Registry, promotion gates, rollback y reproducibilidad.
- Regla: nunca actualizar endpoint sin pasar por validacion y registro.

### 3. Debugger Educativo

- Mision: resolver incidentes explicando la causa raiz.
- Foco: CloudWatch logs, estados de Step Functions, errores IAM.
- Regla: cada fix deja aprendizaje operativo en docs.

### 4. Guardian de Seguridad y Costos

- Mision: minimizar riesgo por permisos excesivos y gasto no controlado.
- Foco: least-privilege, tagging, budgets, alarmas, scheduler.
- Regla: cualquier wildcard en IAM requiere justificacion documentada.

## Flujo por Fases (Documentacion Obligatoria)

Toda iteracion debe mapearse a una fase y tener evidencia en `docs/`.

Archivos base esperados:

- `docs/00-foundations.md`
- `docs/01-data-ingestion.md`
- `docs/02-training-validation.md`
- `docs/03-sagemaker-pipeline.md`
- `docs/04-serving-ecs-sagemaker.md`
- `docs/05-cicd-github-actions.md`
- `docs/06-observability-operations.md`
- `docs/07-cost-governance.md`
- `docs/iterations/ITER-YYYYMMDD-XX.md`

Contenido minimo por archivo:

1. Objetivo y contexto.
2. Decisiones tecnicas y alternativas descartadas.
3. IAM usado (roles/policies/permisos clave).
4. Comandos ejecutados y resultado esperado.
5. Evidencia (outputs, logs, metricas, capturas si aplica).
6. Riesgos/pendientes.
7. Proximo paso.

## Estandares Terraform

Los recursos y modulos Terraform tambien deben seguir una secuencia numerada por etapas (`1_`, `2_`, `3_`, ...), alineada con el avance del proyecto.

Ejemplo de estructura recomendada:

- `terraform/1_foundation`
- `terraform/2_networking`
- `terraform/3_data`
- `terraform/4_ml_training`
- `terraform/5_serving`
- `terraform/6_orchestration`
- `terraform/7_observability_cost`

Regla: no saltar etapas. Cada etapa debe tener `plan` aprobado, evidencia en `docs/` y outputs claros para la siguiente.

Antes de `terraform apply`, el agente debe validar:

1. Convenciones de nombre y tags obligatorios.
2. `terraform fmt`
3. `terraform validate`
4. `terraform plan` con diff explicado
5. Reglas IAM least-privilege
6. Impacto en costo estimado

Tags obligatorios en todos los recursos soportados:

- `project = "titanic-sagemaker"`
- `env = "<dev|prod>"`
- `owner = "<team-or-user>"`
- `managed_by = "terraform"`
- `cost_center = "<value>"`

## Estandares CI/CD (GitHub Actions)

CI/CD obligatorio y versionado desde GitHub.

Estrategia de ambientes:

- `dev`: despliegue automatico desde rama principal tras checks.
- `prod`: despliegue con gate de aprobacion.

Flujo minimo:

1. Pull Request:
   - lint/test/build (codigo)
   - terraform fmt/validate/plan
   - security checks (IaC y dependencias)
2. Merge a main:
   - apply en `dev`
   - smoke tests de pipeline/modelo/endpoint
3. Promocion a `prod`:
   - aprobacion manual + evidencia de `dev`
   - apply en `prod`

Reglas de modelo:

1. Entrenar y validar.
2. Registrar modelo.
3. Evaluar criterio de promocion.
4. Actualizar endpoint solo si pasa umbral.

## Modelo IAM para Usuario de Data Science

Principio: separar identidad humana de roles de ejecucion.

### Usuario operador DS

- Permisos minimos para:
  - ejecutar workflows CI/CD
  - leer logs/metricas
  - consultar estado de recursos
  - asumir roles acotados por entorno

### Roles de workload (servicios)

Definir roles separados para:

- SageMaker execution role
- ECS task execution/task role
- Lambda role
- Step Functions role
- EventBridge/Scheduler invocations

Controles obligatorios:

1. `iam:PassRole` limitado a roles especificos y servicios esperados.
2. Evitar `Action: "*"`, `Resource: "*"`.
3. Secretos via servicios dedicados (no hardcode).
4. Politicas separadas por modulo y entorno.

## Observabilidad y Operacion

Obligatorio configurar:

1. CloudWatch Logs para training, pipelines, lambdas y tareas ECS.
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
